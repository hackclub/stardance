module Post::ShipEvent::Payouts
  extend ActiveSupport::Concern

  PAYOUT_CURVE_VERSION = "stardance_percentile_1_20_v1"
  # Hardware doesn't ride the vote-percentile curve: a build is funded up front
  # and certified by a reviewer, so it pays a flat rate instead. Stamped into
  # payout_curve_version so a snapshot says which rule produced it.
  HARDWARE_STARDUST_PER_HOUR = 5
  HARDWARE_PAYOUT_CURVE_VERSION = "stardance_hardware_flat_5_v1"
  PAYOUT_REVIEW_WINDOW = 24.hours
  BROADCAST_CHANNEL_ID = "C0AFB0JU00P"

  included do
    has_one :certification_ysws_review,
            class_name: "Certification::Ysws",
            foreign_key: :post_ship_event_id,
            inverse_of: :post_ship_event

    scope :approved, -> { where(certification_status: "approved") }
    scope :unpaid, -> { where(payout: nil) }
    scope :voting_payout_path, -> {
      left_outer_joins(:mission_submission)
        .where(
          "mission_submissions.id IS NULL OR (mission_submissions.payout_path = ? AND mission_submissions.status <> ?)",
          "voting",
          "rejected"
        )
    }
    # Hardware is never rated, so it can't clear the vote threshold. The
    # instance-level gates already exempt it; this scope is what
    # refresh_payouts! actually iterates, so it has to exempt it too or the
    # flat hardware payout is never issued by the automated sweep.
    scope :ready_for_payout, -> {
      approved.unpaid.voting_payout_path
        .left_outer_joins(post: :project)
        .where(
          Vote.countable_count_gteq(Post::ShipEvent::VOTES_REQUIRED_FOR_PAYOUT)
              .or(Project.arel_table[:hardware_stage].not_eq(nil))
        )
    }
  end

  class_methods do
    def payout_feature_enabled?(user = nil)
      Flipper.enabled?(:ship_event_payouts, user)
    end

    def refresh_payouts!
      return false unless payout_feature_enabled?

      sample = payout_score_sample

      ready_for_payout.includes(:mission_submission, :certification_ysws_review, post: [ :project, :user ]).find_each do |ship_event|
        ship_event.refresh_payout_score!(sample)
        ship_event.issue_payout!
      end
    end

    def payout_score_sample
      ship_event_ids = voting_payout_path.select(:id)

      locked_vote_ids_by_ship = where(id: ship_event_ids)
        .where.not(payout_basis_locked_at: nil)
        .pluck(:id, :payout_basis_vote_ids)
        .to_h

      rows = Vote.payout_countable
                 .where(ship_event_id: ship_event_ids)
                 .order(:created_at, :id)
                 .pluck(:ship_event_id, :id, *Vote.score_columns)

      scores_by_ship = rows.group_by(&:first).each_with_object({}) do |(ship_event_id, ship_rows), result|
        result[ship_event_id] = payout_counted_score_rows(ship_rows, locked_vote_ids_by_ship[ship_event_id])
      end
      medians_by_ship = scores_by_ship.transform_values { |ship_rows| payout_medians(ship_rows) }

      {
        scores_by_ship: scores_by_ship,
        overall_scores: medians_by_ship.values.filter_map { |medians| average(medians.values.compact) },
        category_values: Vote::SCORE_COLUMNS_BY_CATEGORY.keys.index_with do |category|
          medians_by_ship.values.filter_map { |medians| medians[category] }
        end
      }
    end

    def payout_counted_score_rows(ship_rows, locked_vote_ids)
      selected =
        if locked_vote_ids.present?
          indexed = ship_rows.index_by { |row| row[1] }
          locked_vote_ids.filter_map { |vote_id| indexed[vote_id] }
        else
          ship_rows.first(Post::ShipEvent::VOTES_REQUIRED_FOR_PAYOUT)
        end

      selected.map { |row| row.drop(2) }
    end

    def payout_medians(score_rows)
      Vote::SCORE_COLUMNS_BY_CATEGORY.keys.each_with_index.to_h do |category, index|
        [ category, median(score_rows.filter_map { |row| row[index] }) ]
      end
    end

    def median(values)
      sorted = values.sort
      return nil if sorted.empty?

      midpoint = sorted.length / 2
      if sorted.length.odd?
        sorted[midpoint]
      else
        (sorted[midpoint - 1] + sorted[midpoint]) / 2.0
      end
    end

    def average(values)
      values.sum.to_f / values.length if values.any?
    end

    def percentile_rank(value, values)
      return nil if value.nil? || values.empty?

      below = values.count { |current| current < value }
      equal = values.count { |current| current == value }

      return 50.0 if below.zero? && equal == values.length

      ((below + 0.5 * equal) / values.length.to_f * 100).round(2)
    end
  end

  def refresh_payout_score!(sample = self.class.payout_score_sample)
    medians = self.class.payout_medians(sample[:scores_by_ship].fetch(id, []))
    overall = self.class.average(medians.values.compact)
    percentiles = medians.transform_values.with_index do |median, index|
      category = Vote::SCORE_COLUMNS_BY_CATEGORY.keys[index]
      self.class.percentile_rank(median, sample[:category_values].fetch(category, []))
    end

    update_columns(
      originality_median: medians[:originality],
      technical_median: medians[:technicality],
      usability_median: medians[:usability],
      storytelling_median: medians[:storytelling],
      overall_score: overall,
      originality_percentile: percentiles[:originality],
      technical_percentile: percentiles[:technicality],
      usability_percentile: percentiles[:usability],
      storytelling_percentile: percentiles[:storytelling],
      overall_percentile: self.class.percentile_rank(overall, sample[:overall_scores]),
      updated_at: Time.current
    )
  end

  def issue_payout!
    issue_payout
  end

  def issue_payout(force: false)
    return false unless self.class.payout_feature_enabled?(payout_recipient)

    if payout_ready_except_vote_balance? && vote_balance_blocked?
      notify_vote_deficit
      return false
    end

    return false unless payout_lockable?

    issued = false

    with_lock do
      return false unless payout_lockable?

      lock_payout_basis unless payout_basis_locked_at?
      return false unless force || payout_eligible?

      amount = payout_amount
      return false unless amount&.positive?

      self.payout = amount

      save!
      create_payout_ledger_entry!
      issued = true
    end

    if issued
      notify_payout_issued
      broadcast_payout
      # Jump the recipient to the front of the Airtable sync so their
      # `Loops - stardancePayout*` contact properties refresh within ~1 min.
      payout_recipient&.flag_for_resync!
    end

    issued
  end

  def payout_eligible?
    payout_lockable? &&
      (hardware_payout? || payout_review_due?) &&
      !payout_review_flagged? &&
      !vote_balance_blocked?
  end

  def payout_lockable?
    return false unless self.class.payout_feature_enabled?(payout_recipient)

    payout_ready_except_vote_balance? &&
      !vote_balance_blocked? &&
      hours.positive?
  end

  def payout_recipient
    post&.user
  end

  def hours
    if reviewed_hardware_devlogs
      capped_reviewed_hardware_minutes / 60.0
    else
      capped_logged_seconds / 1.hour.to_f
    end
  end

  def payout_review_open?
    return false unless self.class.payout_feature_enabled?(payout_recipient)

    payout_basis_locked_at.present? &&
      payout.blank? &&
      Time.current < payout_review_deadline &&
      !payout_review_flagged?
  end

  def payout_review_due?
    payout_basis_locked_at.present? && Time.current >= payout_review_deadline
  end

  def payout_review_deadline
    payout_basis_locked_at + PAYOUT_REVIEW_WINDOW if payout_basis_locked_at
  end

  def payout_counted_votes
    if payout_basis_locked_at? && payout_basis_vote_ids.present?
      snapshot = votes.where(id: payout_basis_vote_ids).index_by(&:id)
      payout_basis_vote_ids.filter_map { |vote_id| snapshot[vote_id] }
    else
      votes.payout_countable
           .order(:created_at, :id)
           .limit(Post::ShipEvent::VOTES_REQUIRED_FOR_PAYOUT)
           .to_a
    end
  end

  def payout_counted_vote_ids
    payout_counted_votes.map(&:id)
  end

  def estimated_payout
    payout_amount
  end

  def payout_acceptable_by?(user)
    user.present? &&
      payout_review_open? &&
      (user.admin? || project&.memberships&.where(user: user)&.exists?)
  end

  def accept_payout_now(user:)
    if payout_acceptable_by?(user)
      self.paper_trail_event = "payout_accepted_early"
      issue_payout(force: true)
    else
      false
    end
  end

  def payout_preview(sample = self.class.payout_score_sample, votes_count: nil, pending_flags_count: nil)
    scores = payout_preview_scores(sample)
    preview_hours = payout_basis_locked_at? ? hours_at_payout.to_f : hours
    preview_percentile = payout_basis_locked_at? ? payout_basis_percentile : scores[:overall_percentile]
    preview_multiplier = multiplier ||
      (hardware_payout? ? (hardware_payout_multiplier_override || HARDWARE_STARDUST_PER_HOUR) : payout_multiplier_for_percentile(preview_percentile))
    preview_blessing = payout_basis_locked_at? ? payout_blessing : payout_blessing_for_snapshot
    preview_votes_count = votes_count || votes.payout_countable.count
    preview_pending_flags_count = pending_flags_count || votes.joins(:events).merge(Vote::Event.pending_vote_flags).count

    {
      hours: preview_hours,
      overall_score: payout_basis_locked_at? ? payout_basis_overall_score : scores[:overall_score],
      percentile: preview_percentile,
      multiplier: preview_multiplier,
      blessing: preview_blessing,
      estimated_payout: payout_amount_for(preview_hours, preview_multiplier, preview_blessing),
      votes_count: preview_votes_count,
      review_open: payout_review_open_with_flags?(preview_pending_flags_count),
      review_deadline: payout_review_deadline,
      pending_flags_count: preview_pending_flags_count,
      blockers: payout_preview_blockers(preview_hours, preview_votes_count, preview_pending_flags_count)
    }
  end

  def clear_payout_review
    update!(
      multiplier: nil,
      hours_at_payout: nil,
      payout_basis_overall_score: nil,
      payout_basis_percentile: nil,
      payout_basis_locked_at: nil,
      payout_curve_version: nil,
      payout_blessing: nil,
      payout_basis_vote_ids: [],
      voting_completed_at: nil
    )
  end

  def sync_voting_completion!
    return if hardware_payout? || payout.present?

    required = Post::ShipEvent::VOTES_REQUIRED_FOR_PAYOUT
    counted_votes = votes.payout_countable.order(:created_at, :id).limit(required).to_a
    if counted_votes.size >= required
      return if voting_completed_at.present?

      update!(
        voting_completed_at: counted_votes.last.created_at,
        lifecycle_data_quality: lifecycle_data_quality || "live"
      )
    elsif voting_completed_at.present?
      payout_basis_locked_at? ? clear_payout_review : update!(voting_completed_at: nil)
    end
  end

  private
    # Hardware ships don't charge vote debt, so their builders have no way to
    # work a deficit off. Only the voting path holds a payout for it.
    def vote_balance_blocked?
      !hardware_payout? && payout_recipient&.vote_balance.to_i.negative?
    end

    def payout_ready_except_vote_balance?
      certification_status == "approved" &&
        payout.blank? &&
        voting_payout_path? &&
        (hardware_payout? || votes.payout_countable.count >= Post::ShipEvent::VOTES_REQUIRED_FOR_PAYOUT) &&
        payout_recipient.present?
    end

    def lock_payout_basis
      self.payout_basis_vote_ids = payout_counted_vote_ids
      self.voting_completed_at = votes.where(id: payout_basis_vote_ids).maximum(:created_at)
      self.lifecycle_data_quality ||= "live"
      refresh_payout_score! if overall_percentile.nil?

      self.multiplier = payout_multiplier
      self.hours_at_payout = hours
      self.payout_basis_overall_score = overall_score
      self.payout_basis_percentile = overall_percentile
      self.payout_basis_locked_at = Time.current
      self.payout_curve_version = hardware_payout? ? HARDWARE_PAYOUT_CURVE_VERSION : PAYOUT_CURVE_VERSION
      self.payout_blessing = payout_blessing_for_snapshot

      save!
    end

    def voting_payout_path?
      submission = mission_submission
      submission.nil? || (submission.payout_path == "voting" && !submission.rejected?)
    end

    def reviewed_hardware_devlogs
      review = certification_ysws_review
      review.devlog_reviews if project&.hardware? && review&.devlog_reviews&.any?(&:reviewed?)
    end

    def capped_reviewed_hardware_minutes
      reviewed_hardware_devlogs.sum do |devlog_review|
        next 0 unless counts_toward_hardware_payout?(devlog_review)

        [ devlog_review.approved_minutes.to_i, Post::ShipEvent::MAX_PAYOUT_HOURS_PER_DEVLOG * 60 ].min
      end
    end

    # Only work done once funding was asked for is paid. Time logged before that
    # belongs to the design the grant was awarded against, not to the build.
    def counts_toward_hardware_payout?(devlog_review)
      cutoff = hardware_payout_cutoff
      return true if cutoff.nil?

      logged_at = Post::Devlog.unscoped { devlog_review.reload_post_devlog&.created_at }
      logged_at.present? && logged_at >= cutoff
    end

    # The funding request that unlocked this build. A hardware project that took
    # the "I don't need funding" path has none, so nothing is excluded for it.
    def hardware_payout_cutoff
      return @hardware_payout_cutoff if defined?(@hardware_payout_cutoff)

      @hardware_payout_cutoff =
        project&.certification_funding_requests
               &.approved
               &.minimum(:created_at)
    end

    def capped_logged_seconds
      return 0 unless post&.project && post.created_at

      # devlogs_in_ship_window already drops pre-funding and design-phase time
      # on hardware, so the funding cutoff is applied there.
      devlogs_in_ship_window.pluck("post_devlogs.duration_seconds").sum do |duration_seconds|
        [ duration_seconds.to_i, Post::ShipEvent::MAX_PAYOUT_SECONDS_PER_DEVLOG ].min
      end
    end

    def payout_amount
      return nil if multiplier.nil? || hours_at_payout.nil?

      payout_amount_for(hours_at_payout, multiplier, payout_blessing)
    end

    def payout_multiplier
      if hardware_payout?
        return hardware_payout_multiplier_override || HARDWARE_STARDUST_PER_HOUR
      end

      percentile = payout_basis_percentile || overall_percentile

      payout_multiplier_for_percentile(percentile)
    end

    def hardware_payout_multiplier_override
      Certification::Ship
        .where(post_ship_event_id: id)
        .where.not(payout_multiplier: nil)
        .order(decided_at: :desc)
        .pick(:payout_multiplier)
    end

    # A hardware build's payout is the flat rate, not the vote curve.
    def hardware_payout?
      project&.hardware? || false
    end

    def payout_multiplier_for_percentile(percentile)
      return nil if percentile.nil?

      (dollars_per_hour_for_percentile(percentile) * game_constants.tickets_per_dollar.to_f).round(6)
    end

    def dollars_per_hour_for_percentile(percentile)
      low = game_constants.lowest_dollar_per_hour.to_f
      high = game_constants.highest_dollar_per_hour.to_f
      low + (high - low) * ((percentile.to_f / 100.0).clamp(0.0, 1.0) ** 1.745427173)
    end

    def payout_blessing_for_snapshot
      payout_recipient.vote_verdict&.verdict || "neutral"
    end

    def payout_amount_for(amount_hours, amount_multiplier, blessing)
      return nil if amount_hours.nil? || amount_multiplier.nil?

      apply_payout_blessing((amount_hours * amount_multiplier).round, blessing)
    end

    def apply_payout_blessing(amount, blessing = payout_blessing)
      case blessing
      when "blessed" then (amount * 1.2).round
      when "cursed" then (amount * 0.5).round
      else amount
      end
    end

    def payout_preview_scores(sample)
      medians = self.class.payout_medians(sample[:scores_by_ship].fetch(id, []))
      overall = self.class.average(medians.values.compact)

      {
        overall_score: overall,
        overall_percentile: self.class.percentile_rank(overall, sample[:overall_scores])
      }
    end

    def payout_review_open_with_flags?(pending_flags_count)
      self.class.payout_feature_enabled?(payout_recipient) &&
        payout_basis_locked_at.present? &&
        payout.blank? &&
        Time.current < payout_review_deadline &&
        pending_flags_count.zero?
    end

    def payout_preview_blockers(preview_hours, votes_count, pending_flags_count)
      blockers = []
      blockers << "Not approved" unless certification_status == "approved"
      blockers << "Already paid" if payout.present?
      blockers << "Static prize path" unless voting_payout_path?
      # Hardware is never rated, so a vote count it can't reach isn't a blocker -
      # showing one tells the builder to collect ratings that are never assigned.
      if !hardware_payout? && votes_count < Post::ShipEvent::VOTES_REQUIRED_FOR_PAYOUT
        blockers << "Needs #{Post::ShipEvent::VOTES_REQUIRED_FOR_PAYOUT} countable votes"
      end
      blockers << "Missing recipient" if payout_recipient.blank?
      blockers << "Vote balance deficit" if vote_balance_blocked?
      blockers << "No payable hours" unless preview_hours.to_f.positive?
      blockers << "Pending vote flags" if pending_flags_count.positive?
      blockers
    end

    def create_payout_ledger_entry!
      payout_recipient.ledger_entries.create!(
        ledgerable: self,
        amount: payout,
        reason: "Ship event payout: #{project&.title || 'Unknown project'}",
        created_by: "ship_event_payout"
      )
    end

    def payout_review_flagged?
      votes.joins(:events).merge(Vote::Event.pending_vote_flags).exists?
    end

    def notify_payout_issued
      Notifications::Payouts::ShipEventIssued.notify(
        recipient: payout_recipient,
        record: self,
        params: payout_notification_params
      )
    end

    def notify_vote_deficit
      return if Notifications::Payouts::VoteDeficitBlocked.exists?(recipient: payout_recipient, record: self)

      Notifications::Payouts::VoteDeficitBlocked.notify(
        recipient: payout_recipient,
        record: self,
        params: {
          "votes_needed" => payout_recipient.vote_balance.abs,
          "project_title" => project&.title
        }
      )
    end

    def broadcast_payout
      SendSlackDmJob.perform_later(
        BROADCAST_CHANNEL_ID,
        nil,
        blocks_path: "notifications/payouts/broadcast",
        locals: payout_notification_params.merge(
          project_url: "https://stardance.hackclub.com/projects/#{project&.id}",
          recipient_name: payout_recipient.display_name
        ).symbolize_keys
      )
    end

    def payout_notification_params
      {
        "project_id" => project&.id,
        "project_title" => project&.title || "Unknown project",
        "ship_date" => post&.created_at&.strftime("%b %-d, %Y"),
        "hours" => hours.round(2),
        "stardust" => payout.to_i,
        "multiplier" => multiplier&.round(2),
        "blessing" => payout_blessing
      }
    end

    def game_constants
      Rails.configuration.game_constants
    end
end
