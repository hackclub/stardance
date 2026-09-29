# frozen_string_literal: true

module BukuX3
  # Reconcile snapshots, never increment counters on page views or job retries.
  # Replaying in ship order also makes late approvals and fraud corrections
  # deterministic. Repairs at 0% and damage at 100% cannot be banked.
  class Refresh
    def self.call
      event = Unlock.call
      return unless Flipper.enabled?(:bukux3)
      return unless event&.active?

      event.with_lock do
        new(event, Time.current).reconcile!
      end
      event
    end

    def initialize(event, now)
      @event = event
      @now = now
    end

    def reconcile!
      existing = @event.contributions.index_by(&:ysws_review_id)
      # Use bukux2's approved-minute accounting without waiting for the overall
      # review to finish, but exclude rejected/misfiled ships from this event.
      rows = RocketProgress.approved_reviews
        .where("post_ship_events.created_at > ? AND post_ship_events.created_at <= ?", @event.unlocked_at, @now)
        .where.not(post_ship_events: { certification_status: Post::ShipEvent::HIDDEN_STATUSES })
        .group("post_ship_events.created_at")
        .pluck(:id, :user_id, "post_ship_events.created_at", Arel.sql(RocketProgress::NET_MINUTES_SQL))
      users = User.where(id: rows.map { |row| row[1] }).select(:id).index_by(&:id)

      rows.each do |review_id, user_id, shipped_at, minutes|
        contribution = existing.delete(review_id) || @event.contributions.build(ysws_review_id: review_id)
        if contribution.new_record? || contribution.user_id != user_id
          contribution.buku = Assignment.buku?(users.fetch(user_id))
        end
        contribution.assign_attributes(user_id: user_id, shipped_at: shipped_at, minutes: minutes)
        contribution.save! if contribution.changed?
      end

      # A ban, hidden ship, deleted review, or reduced approval can remove a
      # previously counted ship. Retain its audit record but remove its effect.
      existing.each_value do |contribution|
        contribution.update!(minutes: 0) unless contribution.minutes.zero?
      end

      @event.destruction_minutes = @event.contributions.order(:shipped_at, :ysws_review_id).reduce(Event::STARTING_DESTRUCTION_MINUTES) do |balance, contribution|
        (balance + contribution.signed_minutes).clamp(0, Event::MAX_DESTRUCTION_MINUTES)
      end
      @event.save! if @event.changed?
    end
  end
end
