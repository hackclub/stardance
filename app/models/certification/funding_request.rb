# == Schema Information
#
# Table name: certification_funding_requests
#
#  id                        :bigint           not null, primary key
#  approved_amount_cents     :integer
#  claim_expires_at          :datetime
#  claimed_at                :datetime
#  complexity_tier           :integer          not null
#  decided_at                :datetime
#  discount_stardust_awarded :integer
#  feedback                  :text
#  hcb_grant_hashid          :string
#  internal_reason           :text
#  lock_version              :integer          default(0), not null
#  prizes_waived             :boolean          default(FALSE), not null
#  requested_amount_cents    :integer          not null
#  reversed_at               :datetime
#  stardust_earned           :integer
#  status                    :integer          default(0), not null
#  submitter_note            :text
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  project_id                :bigint           not null
#  reviewer_id               :bigint
#  user_id                   :bigint           not null
#
# Indexes
#
#  idx_funding_requests_on_status_claim_expires         (status,claim_expires_at)
#  index_certification_funding_requests_on_decided_at   (decided_at)
#  index_certification_funding_requests_on_project_id   (project_id)
#  index_certification_funding_requests_on_reviewer_id  (reviewer_id)
#  index_certification_funding_requests_on_user_id      (user_id)
#  index_funding_requests_unique_pending_project        (project_id) UNIQUE WHERE (status = 0)
#
# Foreign Keys
#
#  fk_rails_...  (project_id => projects.id)
#  fk_rails_...  (reviewer_id => users.id)
#  fk_rails_...  (user_id => users.id)
#
module Certification
  # A hardware project owner's request for a build grant, submitted from the
  # design stage. Routes through the same reviewer queue as
  # ship certifications (Certification::Reviewable). On approval the project
  # switches to the build stage and an HCB card grant is issued for the approved
  # amount, capped by the tier's max.
  #
  # When the project's mission hands out a design kit (an after_design prize),
  # approval delivers that kit for redemption instead of a cash grant: no HCB
  # grant is issued and the tier/amount fields are vestigial (defaulted, hidden
  # in the request form).
  #
  # A reviewer can also approve without any funding at all (the builder already
  # has the parts, or is covered some other way). That is an ordinary approval
  # recorded as an approved amount of $0, which issues no grant. On a kit
  # mission the same verdict waives the kit (`prizes_waived`): the project still
  # moves to the build stage, but nothing is owed and nothing is claimable.
  class FundingRequest < ApplicationRecord
    self.table_name = "certification_funding_requests"

    include Certification::Reviewable
    include Mission::PrizeRedeemable

    belongs_to :project
    belongs_to :user
    belongs_to :reviewer, class_name: "User", optional: true

    has_paper_trail

    # Reviewers can attach annotated photos (wiring shots, schematics) to their
    # written feedback, shown to the builder beside the feedback text. Images
    # only, and always optional: mirrors HasPostAttachments' webp variants and
    # content-type/size validations without its "at least one attachment" rule.
    MAX_FEEDBACK_IMAGES = 6
    FEEDBACK_IMAGE_CONTENT_TYPES = %w[
      image/jpeg
      image/png
      image/webp
      image/heic
      image/heif
      image/gif
    ].freeze

    has_many_attached :feedback_images do |attachable|
      attachable.variant :large,
                         resize_to_limit: [ 1600, 900 ],
                         format: :webp,
                         preprocessed: true,
                         saver: { strip: true, quality: 75 }

      attachable.variant :medium,
                         resize_to_limit: [ 800, 800 ],
                         format: :webp,
                         preprocessed: false,
                         saver: { strip: true, quality: 75 }

      attachable.variant :thumb,
                         resize_to_limit: [ 400, 400 ],
                         format: :webp,
                         preprocessed: false,
                         saver: { strip: true, quality: 75 }
    end

    validates :feedback_images,
              content_type: { in: FEEDBACK_IMAGE_CONTENT_TYPES, spoofing_protection: true },
              size: { less_than: 15.megabytes, message: "is too large (max 15 MB)" },
              processable_file: true
    validate :feedback_images_within_limit

    # misfiled: a reviewer says this belongs in the build queue and the builder
    # hasn't answered yet. withdrawn: the builder agreed, so the request is done
    # with and the project moves on to the build stage. Neither is a verdict, so
    # both stay out of the approval-rate and decision tallies.
    enum :status, {
      pending: 0,
      approved: 1,
      returned: 2,
      misfiled: 3,
      withdrawn: 4
    }, default: :pending

    # HCB org the hardware grants are issued from. Spend controls (approved and
    # blocked merchants/categories) live on this org's card-grant settings in the
    # HCB dashboard, not here: HCB's v4 API can't set the banned lists per grant
    # (card_grants_controller only permits merchant_lock/category_lock), so every
    # grant inherits allowed + banned from the org setting via CardGrant's union
    # of its own locks with `setting`.
    HCB_GRANT_ORG = "stardance-hardware"

    # Complexity tiers (B/A/S/X). Keyed by the integer stored in
    # complexity_tier; each carries a max grant + examples.
    TIERS = {
      1 => { code: "B", name: "B Tier", max_cents: 2_500,  examples: "Basic PCBs, Macropads, 3D prints" },
      2 => { code: "A", name: "A Tier", max_cents: 12_000, examples: "Keyboards, devboards, basic gadgets" },
      3 => { code: "S", name: "S Tier", max_cents: 20_000, examples: "More complex projects!" },
      4 => { code: "X", name: "X Tier", max_cents: 60_000, examples: "3D printers, advanced PCBs, and more!" }
    }.freeze

    # tier => maximum grant, in cents / dollars.
    TIER_MAX_CENTS = TIERS.transform_values { |t| t[:max_cents] }.freeze
    TIER_MAX_DOLLARS = TIER_MAX_CENTS.transform_values { |cents| cents / 100 }.freeze

    # Stardust a reviewer earns per completed funding review.
    REVIEW_BOUNTY = 1

    # The three choices a reviewer picks from on the design review form.
    VERDICTS = %w[approved approved_without_grant returned].freeze

    before_validation :default_kit_request_fields, on: :create, if: :kit_mission?
    # Zeroed here rather than in the writer so it wins regardless of the order
    # the verdict and the approved amount arrive in from the form.
    before_validation :zero_approved_amount, if: -> { @verdict == "approved_without_grant" }

    validates :complexity_tier, inclusion: { in: TIER_MAX_CENTS.keys }
    validates :requested_amount_cents,
              numericality: { only_integer: true, greater_than: 0 }, unless: :kit_mission?
    validates :approved_amount_cents,
              numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
    validates :feedback, length: { maximum: 10_000 }, allow_blank: true
    # Optional free-text note the builder writes for the reviewer at submission.
    validates :submitter_note, length: { maximum: 10_000 }, allow_blank: true
    validates :verdict, inclusion: { in: VERDICTS }, allow_nil: true
    validate :requested_within_tier_max
    validate :approved_within_tier_max
    validate :project_in_design_stage, on: :create
    validate :project_has_devlogs, on: :create
    validate :no_pending_request_exists, on: :create
    validate :owner_eligible_for_funding, on: :create

    scope :for_reviewer, ->(user) {
      joins(:project)
        .where(projects: { deleted_at: nil })
        .where.not(project_id: user.memberships.select(:project_id))
    }

    # What the global hardware design queue can actually hand a reviewer. A
    # request on a soft-deleted project is unreachable from every dash, and a
    # hardware mission's requests are reviewed on that mission's own dash, so
    # counting either against this queue reports a backlog nobody can work.
    scope :in_global_hardware_queue, -> { joins(:project).merge(::Project.hardware.without_hardware_mission) }
    # The other half: requests a hardware mission reviews on its own dash.
    scope :in_hardware_mission_queue, -> { joins(:project).merge(::Project.hardware.with_hardware_mission) }

    def self.available_for(user)
      # Chained AFTER the merge on purpose: `merge` would replace this project_id
      # filter with for_reviewer's own project_id condition and drop the fraud
      # hold-back. A pending fraud report keeps the project out of the queue
      # until the fraud team clears it.
      super.merge(for_reviewer(user)).where.not(project_id: fraud_flagged_project_ids)
    end

    # Health target for the pending queue. Above this we read as "behind".
    QUEUE_TARGET = 25

    # Target turnaround: a request should get a verdict within this many days.
    SLA_DAYS = 3

    # Snapshot of queue health for the reviewer dashboard. Counts are global
    # (every reviewer shares one queue).
    def self.dashboard_stats(now: Time.current)
      today = now.beginning_of_day
      week = now.beginning_of_week
      approved_count = where(status: :approved).count
      returned_count = where(status: :returned).count
      decided_count = approved_count + returned_count

      decided_scope = decided

      {
        pending: where(status: :pending).count,
        approved: approved_count,
        returned: returned_count,
        decided: decided_count,
        approval_rate: decided_count.zero? ? nil : (approved_count * 100.0 / decided_count).round,
        decisions_today: decided_scope.where(decided_at: today..).count,
        new_today: where(created_at: today..).count,
        decisions_this_week: decided_scope.where(decided_at: week..).count,
        new_this_week: where(created_at: week..).count,
        oldest_pending: where(status: :pending).order(created_at: :asc).first,
        queue_target: QUEUE_TARGET,
        sla_days: SLA_DAYS,
        overdue_pending: where(status: :pending).where("created_at < ?", now - SLA_DAYS.days).count
      }
    end

    # Reviewers ranked by completed decisions over a window.
    def self.leaderboard(period, now: Time.current, limit: 10)
      scope = where.not(reviewer_id: nil).decided
      case period.to_sym
      when :daily  then scope = scope.where(decided_at: now.beginning_of_day..)
      when :weekly then scope = scope.where(decided_at: now.beginning_of_week..)
      end

      scope.joins(:reviewer)
           .group("users.display_name")
           .order(Arel.sql("COUNT(*) DESC"), Arel.sql("users.display_name ASC"))
           .limit(limit)
           .count
           .map { |name, count| { name: name, count: count } }
    end

    # How many requests this reviewer has decided today.
    def self.reviewed_today(user, now: Time.current)
      where(reviewer_id: user.id)
        .decided
        .where(decided_at: now.beginning_of_day..)
        .count
    end

    def tier = TIERS.fetch(complexity_tier, {})
    def tier_code = tier[:code]
    def tier_name = tier[:name]
    def tier_examples = tier[:examples]
    def tier_label = tier_name || "Tier #{complexity_tier}"
    def tier_max_cents = tier[:max_cents]
    def tier_max_dollars = tier_max_cents ? tier_max_cents / 100 : nil
    def requested_amount_dollars = (requested_amount_cents || 0) / 100
    def final_amount_cents = approved_amount_cents || requested_amount_cents
    def final_amount_dollars = (final_amount_cents || 0) / 100

    # The hardware builder this request belongs to: the project's owner
    # membership, falling back to the submitting user when no owner membership
    # remains (mirrors how grants/discounts resolve the recipient).
    def owner
      @owner ||= project.memberships.owner.first&.user || user
    end

    # True when the project's active mission hands out a kit at design approval
    # (an after_design prize) rather than a cash grant. Independent of the
    # verdict: the create-time defaults and the requested-amount validation key
    # off the mission, not off what a reviewer later decided.
    def kit_mission?
      redeemable_prizes.exists?
    end

    # True when approving this request actually delivers that kit. A reviewer
    # who approved the design without sending one (the builder already has the
    # parts, or is redoing a mission they've claimed before) waives it.
    def awards_design_kit?
      !prizes_waived? && kit_mission?
    end

    # A waived approval owes no prizes, so nothing is left to claim: this closes
    # the claim links on the project page and the shop's free-price gate, both
    # of which ask the request what it still owes.
    def unredeemed_prizes
      return Mission::Prize.none if prizes_waived?

      super
    end

    # True when approving this request pays out an HCB card grant, as opposed to
    # shipping a kit or approving the build with no funding at all.
    def issues_grant?
      approved? && !awards_design_kit? && final_amount_cents.to_i.positive?
    end

    # An approval that funds nothing: the project moves to the build stage, but
    # no grant is issued and no kit is owed.
    def approved_without_grant?
      approved? && !awards_design_kit? && !issues_grant?
    end

    # The review form's verdict radio. Collapses the status and the "no grant"
    # approval into one choice; the amount is zeroed before validation. Only a
    # real verdict maps here: the queue-routing statuses aren't choices on the
    # form, and reflecting them would fail the inclusion validation below.
    def verdict
      @verdict ||= if approved_without_grant?
        "approved_without_grant"
      elsif decided?
        status
      end
    end

    def verdict=(value)
      @verdict = value.presence
      return unless VERDICTS.include?(@verdict)

      without_grant = @verdict == "approved_without_grant"
      self.status = without_grant ? "approved" : @verdict
      # On a kit mission this is what makes the verdict stick: the amount is
      # already 0 either way, so the waiver is the only thing separating
      # "approved, kit on the way" from "approved, no kit".
      self.prizes_waived = without_grant
    end

    # True unless a newer funding request has superseded this one (a resubmit
    # after a return). A superseded request's verdict is inert: it must not
    # advance the project or issue a grant/kit, so approving the wrong one can't
    # move the project while a newer request is still live.
    def latest_for_project?
      return true unless project
      !project.certification_funding_requests.where("id > ?", id).exists?
    end

    # Redemption-gate interface (see Mission::PrizeRedeemable): an approved
    # design claims the mission's after-design kits.
    def redemption_mission = project&.current_mission
    def redemption_prize_category = :after_design

    # The kit shipped when this design is approved (the mission's first
    # after_design prize), for reviewer-facing copy.
    def design_kit_shop_item
      redeemable_prizes.first&.shop_item
    end

    # Locals for the verdict notification's Slack template.
    def notification_locals
      routes = Rails.application.routes.url_helpers
      # default_url_options is only configured in production, so a bare
      # reverse_merge on it raises NoMethodError in development and test.
      url_opts = (Rails.application.config.action_controller.default_url_options || {})
                   .reverse_merge(host: "stardance.hackclub.com", protocol: "https")

      {
        project_title: project.title,
        project_url: routes.project_url(project, **url_opts),
        approved: approved?,
        awards_kit: awards_design_kit?,
        kit_mission: kit_mission?,
        issues_grant: issues_grant?,
        amount_dollars: final_amount_dollars,
        tier_label: tier_label,
        reviewer_name: reviewer&.display_name,
        feedback: feedback.to_s
      }
    end

    # Reviewers enter whole-dollar amounts; we persist cents.
    def approved_amount_dollars
      approved_amount_cents ? approved_amount_cents / 100 : nil
    end

    def approved_amount_dollars=(value)
      self.approved_amount_cents = value.present? ? value.to_i * 100 : nil
    end

    before_save :default_approved_amount,
      if: -> { will_save_change_to_status? && status_change&.last == "approved" }
    before_save :stamp_claimed_at,
      if: -> { will_save_change_to_reviewer_id? && reviewer_id.present? && claimed_at.nil? }
    before_save :stamp_decided_at,
      if: -> { will_save_change_to_status? && status_change&.last.in?(DECIDED_STATUSES) && decided_at.nil? }
    before_save :assign_stardust_earned,
      if: -> { will_save_change_to_status? && status_change&.last.in?(DECIDED_STATUSES) && reviewer_id.present? }
    after_save :apply_verdict_to_project!, if: :saved_change_to_status?
    # Notify first. The verdict message only states what already happened (the
    # request was approved, the project moved to build) and never claims a card
    # has been issued, so it stays true even if the grant fails - and declaring
    # it first means a dead HCB token can't silently swallow the verdict.
    #
    # The grant is guarded on a missing hashid rather than on the status change,
    # so a grant that failed (an expired HCB token is a live failure mode here)
    # retries the next time the request is saved instead of being stranded.
    # issue_hcb_grant! already returns early when a grant exists.
    after_save_commit :notify_owner!, if: -> { saved_change_to_status? && decided? }
    after_save_commit :post_verdict_to_hardware_review_channel!, if: -> { saved_change_to_status? && decided? }
    after_save_commit :post_approval_to_hardware_feed!, if: -> { saved_change_to_status? && approved? }
    after_save_commit :issue_hcb_grant!, if: -> { issues_grant? && hcb_grant_hashid.blank? && latest_for_project? }
    after_create_commit :post_submission_to_hardware_review_channel!

    def queue_mismatch_flagged_label = "design funding"
    def queue_mismatch_suggested_label = "build certification"

    private

    # The builder confirmed they never needed funding and the build is done, so
    # the project moves to the build stage and the design devlogs they logged
    # while actually building are re-filed as build time.
    def apply_queue_conversion!
      project.converting_review_queue = true
      project.update!(hardware_stage: "build")
      project.refile_design_devlogs_as_build!
    end

    def project_in_design_stage
      errors.add(:base, "Only projects in the design stage can request funding.") unless project&.design_stage?
    end

    def project_has_devlogs
      errors.add(:base, "You need to post at least one devlog before requesting funding.") unless project&.devlog_posts&.exists?
    end

    def no_pending_request_exists
      errors.add(:base, "You already have a funding request under review.") if project&.has_pending_funding_request?
    end

    # The grant (or kit) goes to the project owner, so they have to clear the
    # same identity and YSWS bar shipping applies before the request can enter
    # the queue (see Project#shipping_requirements).
    def owner_eligible_for_funding
      return if project.blank?

      if !owner&.identity_verified?
        errors.add(:base, "Verify your identity before requesting funding.")
      elsif !owner.ysws_eligible?
        errors.add(:base, "You're not eligible for YSWS prizes yet, so we can't fund this build. Check the Hack Club portal for details.")
      end
    end

    def feedback_images_within_limit
      return unless feedback_images.attached?

      if feedback_images.size > MAX_FEEDBACK_IMAGES
        errors.add(:feedback_images, "can't exceed #{MAX_FEEDBACK_IMAGES} images")
      end
    end

    def requested_within_tier_max
      return if complexity_tier.blank? || requested_amount_cents.blank?
      return unless TIER_MAX_CENTS.key?(complexity_tier)

      if requested_amount_cents > tier_max_cents
        errors.add(:requested_amount_cents, "exceeds the #{tier_label} maximum of $#{tier_max_dollars}")
      end
    end

    # Reviewers can approve for less than requested, but never above the tier max.
    def approved_within_tier_max
      return if approved_amount_cents.blank? || complexity_tier.blank?
      return unless TIER_MAX_CENTS.key?(complexity_tier)

      if approved_amount_cents > tier_max_cents
        errors.add(:approved_amount_cents, "exceeds the #{tier_label} maximum of $#{tier_max_dollars}")
      end
    end

    def default_approved_amount
      self.approved_amount_cents ||= requested_amount_cents
    end

    def zero_approved_amount
      self.approved_amount_cents = 0
    end

    # Kit missions have no cash amount, but the columns are NOT NULL. Seed the
    # smallest valid tier and a zero amount so the record persists; the form
    # hides both fields for these requests.
    def default_kit_request_fields
      self.complexity_tier ||= TIER_MAX_CENTS.keys.min
      self.requested_amount_cents ||= 0
    end

    def assign_stardust_earned
      self.stardust_earned = REVIEW_BOUNTY
    end

    def stamp_claimed_at
      self.claimed_at = Time.current
    end

    def stamp_decided_at
      self.decided_at = Time.current
      # A fresh verdict clears any prior reversal marker.
      self.reversed_at = nil
    end

    # On a decision, advance the project. approved_amount_cents is defaulted in a
    # before_save so it's set by the time this runs.
    def apply_verdict_to_project!
      return unless decided?
      return unless latest_for_project?
      project.with_lock do
        case status.to_sym
        when :approved
          project.advancing_via_funding_approval = true
          project.update!(hardware_stage: "build")
        when :returned
          # owner is notified; no project change
        end
      end
    end

    def issue_hcb_grant!
      return if hcb_grant_hashid.present?

      owner = project.memberships.owner.first&.user || user
      grant = HCBService.create_card_grant(
        email: owner.grant_email,
        amount_cents: final_amount_cents,
        # HCB caps the purpose at 30 chars, so key it off the project id (short
        # and stable) rather than the title, which would get chopped.
        purpose: "Hardware grant, project #{project.id}".truncate(30),
        instructions: grant_instructions,
        organization: HCB_GRANT_ORG
      )
      update_column(:hcb_grant_hashid, grant["id"])
    rescue => e
      Rails.logger.error "Failed to issue HCB grant for FundingRequest ##{id}: #{e.message}"
      raise
    end

    # Cardholder-facing note shown on the grant in HCB. No length cap here (only
    # `purpose` is capped), so it can spell out what the money is for.
    def grant_instructions
      "Use this grant to buy parts and materials for your Stardance hardware " \
        "project \"#{project.title}\". Spend it only on components for this " \
        "build, keep your receipts, and ask in #stardance-help if you have any questions."
    end

    # Routed through the notification pipeline rather than a direct Slack DM, so
    # the verdict also lands in the in-app inbox and by email, and so a builder
    # with no Slack account still hears about it.
    def notify_owner!
      Notifications::Hardware::FundingRequestReviewed.notify(
        recipient: owner,
        actor: reviewer,
        record: self
      )
    rescue StandardError => e
      Rails.logger.error("FundingRequest ##{id} notify_owner! failed: #{e.message}")
    end
  end
end
