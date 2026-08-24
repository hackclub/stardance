# frozen_string_literal: true

module Certification
  # Full-auto reversal of a decided hardware review - a Certification::FundingRequest
  # or a Certification::Ship. The in-DB state is rewound with `update!`/`destroy!`
  # so PaperTrail carries the whole reversal, and the one external side effect
  # (cancelling the HCB grant, or deleting a synced YSWS Airtable record) runs
  # inside the same row lock, after the reversal, so a failed cancel rolls the DB
  # changes back and a cancelled grant can never be stranded on a live review.
  #
  # A funding request goes back to :pending for a reviewer to re-decide. A ship is
  # :withdrawn and its project returned to draft, so the builder re-submits the
  # (still-present) ship post rather than the reviewer silently re-reviewing it.
  #
  # This touches real grant money, so it is deliberately conservative:
  #
  #   * Only the LATEST decided review on a project can be undone (mirrors
  #     FundingRequest#latest_for_project?), so undoing never leaves an older
  #     decision stranded under a newer one.
  #   * A spent HCB grant, a claimed design kit, or a granted/claimed hardware
  #     mission reward BLOCKS the undo - those can't be pulled back safely and
  #     have to be reconciled by hand.
  #
  # #preflight classifies every side effect without changing anything, so the
  # confirm dialog can show exactly what will happen. #undo! performs it.
  class ReviewUndoer
    # One line of the reversal ledger. `action` is how the effect is handled:
    #   :reverse    - undone automatically, in DB
    #   :block      - can't be undone; its presence makes the whole review un-undoable
    #   :manual     - left for a human to finish (e.g. a downstream Unified YSWS row)
    #   :correction - already sent and can't be unsent, so a correction is posted
    Effect = Struct.new(:effect, :action, :detail, keyword_init: true)

    Outcome = Struct.new(:effects, :undone, keyword_init: true) do
      def undoable? = blockers.empty?
      def undone? = !!undone
      def blockers = effects.select { |e| e.action == :block }
      def reversals = effects.select { |e| e.action == :reverse }
      def corrections = effects.select { |e| e.action == :correction }
      def manual_steps = effects.select { |e| e.action == :manual }
      def blocker_summary = blockers.map(&:detail).join(" ")
    end

    attr_reader :review, :actor

    def initialize(review, actor: nil)
      @review = review
      @actor = actor
    end

    # Read-only classification of every side effect. Safe to call from a GET.
    def preflight
      return outcome([ block(:decided, "This review hasn't been decided, so there's nothing to undo.") ]) unless review.decided?
      return outcome([ block(:latest, "A newer review has superseded this one. Undo the most recent decision first.") ]) unless latest_decided_review?

      effects = [ reverse(:review, review_reversal_detail) ]
      funding? ? funding_effects(effects) : ship_effects(effects)
      effects << correction(:notifications, "The builder was already told the verdict, so they get a private DM that it's been undone. Nothing is posted publicly.")
      outcome(effects)
    end

    # Performs the reversal. Returns an Outcome whose #undone? says whether it
    # went through. The one external side effect (cancelling the HCB grant) runs
    # inside the row lock, after the re-check and the DB reversal, so a grant can
    # never be cancelled unless the review is reversed in the same breath.
    def undo!
      pf = preflight
      return outcome(pf.effects, undone: false) unless pf.undoable?

      original_status = review.status
      grant_hashid = grant_hashid_to_cancel(pf)

      undone = false
      review.with_lock do
        # Cheap re-check under the row lock (no HCB round-trip) so a double-submit
        # can't undo twice, and so the grant below is only cancelled once we know
        # the reversal will go through.
        next unless still_undoable?

        reverse_review_record!
        funding? ? reverse_funding_side_effects!(original_status) : reverse_ship_side_effects!
        # External reversals run last: a failure rolls the whole transaction back,
        # so a cancelled grant can never be stranded on a non-reversed review.
        raise ActiveRecord::Rollback unless perform_external_reversals!(grant_hashid)

        undone = true
      end
      return outcome(pf.effects, undone: false) unless undone

      notify_owner_of_undo!
      outcome(pf.effects, undone: true)
    end

    private

    def funding? = review.is_a?(Certification::FundingRequest)
    def ship? = review.is_a?(Certification::Ship)
    def project = review.project

    # A funding request goes back to the pending queue for a reviewer to
    # re-decide; a ship is withdrawn instead, so the builder re-submits the
    # existing ship rather than the reviewer silently re-reviewing it.
    def review_reversal_detail
      if funding?
        "The verdict is cleared and the review returns to the pending queue."
      else
        "The verdict is cleared and the ship submission is withdrawn so the builder can re-submit it."
      end
    end

    # --- guards --------------------------------------------------------------

    # Only the newest decided review on the project may be undone. Mirrors
    # FundingRequest#latest_for_project? for the same-type case, and extends it
    # across both hardware review tables by decision time.
    def latest_decided_review?
      return false unless review.decided?
      return false if project.nil?
      return false if newer_same_type_record?
      return false if newer_decided_cross_type?
      true
    end

    def newer_same_type_record?
      review.class.where(project_id: project.id).where("id > ?", review.id).exists?
    end

    def newer_decided_cross_type?
      return false if review.decided_at.blank?

      other_decided_reviews.any? { |r| r.decided_at.present? && r.decided_at > review.decided_at }
    end

    def other_decided_reviews
      (project.certification_funding_requests.decided.to_a + project.ship_reviews.decided.to_a)
        .reject { |r| r.instance_of?(review.class) && r.id == review.id }
    end

    # DB-only re-check for use inside the row lock.
    def still_undoable?
      return false unless review.decided?
      return false unless latest_decided_review?
      return false if funding? && review.awards_design_kit? && review.prize_redemptions.exists?
      return false if ship? && mission_reward_delivered?

      true
    end

    # --- funding effects -----------------------------------------------------

    def funding_effects(effects)
      return unless review.approved? # a returned request changed nothing beyond its own record

      effects << reverse(:project_stage, "The project returns to the design stage.") if project&.build_stage?
      kit_effect(effects) if review.awards_design_kit?
      grant_effect(effects) if review.hcb_grant_hashid.present?
    end

    def kit_effect(effects)
      if review.prize_redemptions.exists?
        effects << block(:design_kit, "The mission kit has already been claimed, so this approval can't be reversed automatically.")
      else
        effects << reverse(:design_kit, "The unclaimed kit offer is withdrawn.")
      end
    end

    def grant_effect(effects)
      data = fetch_grant
      if data.nil?
        # Can't confirm the grant is safe to pull back, so refuse rather than
        # rewind the review while leaving live money on the card.
        effects << block(:hcb_grant, "Couldn't reach HCB to check the grant. Try again in a moment, or cancel it by hand first.")
      elsif ShopCardGrant.canceled_grant?(data)
        effects << manual(:hcb_grant, "The HCB grant is already cancelled - nothing to reverse there.")
      elsif grant_spent?(data)
        effects << block(:hcb_grant, "The HCB grant has already been spent (#{spent_summary(data)}). Reconcile or refund it in HCB before undoing.")
      else
        effects << reverse(:hcb_grant, "Cancel the unspent $#{review.final_amount_dollars} HCB card grant.")
      end
    end

    # Cached for a short window keyed by the grant hashid: the review page runs
    # this on every render of a decided grant-bearing request, and the status
    # doesn't change second to second. A lookup failure still falls through to
    # the block branch above (nothing is cached on error).
    GRANT_STATUS_CACHE_TTL = 90.seconds

    def fetch_grant
      Rails.cache.fetch([ "hardware_review_undo", "card_grant", review.hcb_grant_hashid ], expires_in: GRANT_STATUS_CACHE_TTL) do
        HCBService.show_card_grant(hashid: review.hcb_grant_hashid)
      end
    rescue StandardError => e
      Rails.logger.error("ReviewUndoer grant lookup failed for FundingRequest ##{review.id}: #{e.message}")
      nil
    end

    # Spent/cancelled classification reuses ShopCardGrant's field handling, the
    # same reader the shop-fulfillment path (Shop::HCBGrantFulfillable#topupable?)
    # uses, so both judge a grant off identical payload fields.
    def grant_spent?(data) = ShopCardGrant.spent_grant?(data, expected_cents: review.final_amount_cents)

    def spent_summary(data)
      amount = (data["amount_cents"] || review.final_amount_cents).to_i
      spent = amount - data["balance_cents"].to_i
      "$#{spent / 100} of $#{amount / 100} spent"
    end

    # --- ship effects --------------------------------------------------------

    def ship_effects(effects)
      effects << block(:mission_reward, "This build's hardware-mission rewards were already granted or claimed. Undo the mission submission by hand first.") if mission_reward_delivered?

      ship_event = review.verdict_ship_event
      effects << reverse(:ship_event, "The ship post is kept, but its certification is cleared.") if ship_event
      effects << reverse(:project_state, "The project returns to draft - the builder re-submits the ship when they're ready.") if latest_ship?(ship_event) && project_state_reversible?
      ysws_effects(effects) if review.approved?
    end

    # True once a hardware-mission build reward is out the door: the submission
    # was approved (achievement + stardust granted) or a prize was claimed.
    # Neither is safe to reverse automatically.
    def mission_reward_delivered?
      submission = review.verdict_ship_event&.mission_submission
      return false unless submission

      submission.approved? || submission.prize_redemptions.exists?
    end

    def latest_ship?(ship_event)
      ship_event.nil? || ship_event == project&.last_ship_event
    end

    # The ship verdict only moved the project's AASM state when the ship was the
    # latest; only rewind it from a state a verdict could have produced.
    def project_state_reversible?
      project && project.ship_status.to_s.in?(%w[approved needs_changes under_review])
    end

    def ysws_effects(effects)
      reviews = ysws_reviews_for_ship
      return if reviews.empty?

      effects << reverse(:ysws_review, "The auto-created YSWS review is deleted.")
      effects << manual(:unified_ysws, "A YSWS submission already reached the Unified YSWS DB. Remove it there by hand.") if reviews.any? { |r| r.reviewed_at? || r.in_unified_db.present? }
    end

    # The YSWS review(s) a ship approval spun up. Matched on ship_cert_id, with a
    # fall back to the ship event for older rows created before ship_cert_id was
    # populated.
    def ysws_reviews_for_ship
      scope = Certification::Ysws.where(ship_cert_id: review.id).to_a
      scope += Certification::Ysws.where(post_ship_event_id: review.post_ship_event_id, ship_cert_id: nil).to_a if review.post_ship_event_id
      scope.uniq
    end

    # --- external reversals (run inside the row lock) ------------------------

    # The grant to cancel, or nil when there's nothing to pull back. Read before
    # the reversal clears the hashid, and only when preflight confirmed the grant
    # is present and unspent. Cancellation goes through the same HCBService call
    # the "cancel all card grants" admin feature uses.
    def grant_hashid_to_cancel(pf)
      return nil unless funding?
      return nil unless pf.effects.any? { |e| e.effect == :hcb_grant && e.action == :reverse }

      review.hcb_grant_hashid
    end

    def perform_external_reversals!(grant_hashid)
      HCBService.cancel_card_grant!(hashid: grant_hashid) if grant_hashid.present?
      delete_synced_ysws_airtable_records! if ship?
      true
    rescue StandardError => e
      Rails.logger.error("ReviewUndoer external reversal failed for #{review.class} ##{review.id}: #{e.message}")
      false
    end

    # Only completed/synced YSWS reviews have an Airtable submission row; a
    # freshly auto-created (pending) one has nothing there, so this is a no-op in
    # the common case. A missing record is success - there is nothing to remove.
    def delete_synced_ysws_airtable_records!
      ysws_reviews_for_ship.each do |yr|
        next unless yr.airtable_synced_at? || yr.reviewed_at?

        record = Certification::YswsAirtable.record_for(yr.id)
        record&.destroy
      rescue Norairrecord::RecordNotFoundError
        nil
      end
    end

    # --- in-DB reversal ------------------------------------------------------

    def reverse_review_record!
      attrs = {
        status: reversed_status,
        decided_at: nil,
        reviewer_id: nil,
        claimed_at: nil,
        claim_expires_at: nil,
        stardust_earned: nil,
        # Marks the review as a reversal so the admin review history shows a
        # "Reversed" badge rather than the review just vanishing. Cleared when the
        # review is decided again (see #stamp_decided_at in the review models).
        reversed_at: Time.current
      }
      # Cleared so a later re-approval issues a fresh grant rather than trusting
      # the now-cancelled one (issue_hcb_grant! short-circuits on a present hashid).
      attrs[:hcb_grant_hashid] = nil if funding? && review.hcb_grant_hashid.present?
      review.update!(attrs)
    end

    # A funding request goes back to :pending so a reviewer re-decides it. A ship
    # is :withdrawn instead: it leaves the reviewer queue and the pending-review
    # guards (so it can't be re-decided silently and doesn't trip the one-pending
    # -per-project index), and the builder re-submits the still-present ship post.
    def reversed_status = ship? ? :withdrawn : :pending

    def reverse_funding_side_effects!(original_status)
      return unless original_status == "approved"
      return unless project&.build_stage?

      project.with_lock do
        project.reverting_hardware_review = true
        project.update!(hardware_stage: "design")
      end
    end

    def reverse_ship_side_effects!
      ship_event = review.verdict_ship_event
      ship_event&.update!(certification_status: "pending")
      withdraw_project_ship! if latest_ship?(ship_event) && project_state_reversible?
      ysws_reviews_for_ship.each(&:destroy!)
    end

    # Return the project to draft and clear shipped_at, mirroring the AASM
    # `withdraw_ship` event's end state so the ship reads as un-submitted and the
    # builder gets the ship button back. A direct update because `withdraw_ship`
    # only fires from submitted/under_review, and a decided ship sits in
    # approved/needs_changes.
    def withdraw_project_ship!
      project.with_lock { project.update!(ship_status: "draft", shipped_at: nil) }
    end

    # --- correction (after commit) -------------------------------------------

    # The builder was already told the verdict, so a reversal DMs them privately.
    # Nothing is posted to the public review channel - the DM is the correction.
    def notify_owner_of_undo!
      Notifications::Hardware::ReviewUndone.notify(recipient: owner, actor: actor, record: review)
    rescue StandardError => e
      Rails.logger.error("ReviewUndoer owner notification failed for #{review.class} ##{review.id}: #{e.message}")
    end

    def owner = review.owner

    # --- effect/outcome builders ---------------------------------------------

    def outcome(effects, undone: false) = Outcome.new(effects: effects, undone: undone)
    def reverse(effect, detail) = Effect.new(effect: effect, action: :reverse, detail: detail)
    def block(effect, detail) = Effect.new(effect: effect, action: :block, detail: detail)
    def manual(effect, detail) = Effect.new(effect: effect, action: :manual, detail: detail)
    def correction(effect, detail) = Effect.new(effect: effect, action: :correction, detail: detail)
  end
end
