# frozen_string_literal: true

# The rocket-repair goal behind the :bukux2 flag: 500 hours of coding, counted
# from approved YSWS submissions as they land in the unified base.
#
# Read-only by design. Nothing stores a running total and nothing writes to the
# review pipeline — the figure is derived on demand from reviews whose
# airtable_synced_at falls inside the campaign window, which is what makes the
# bar start at zero on launch day without a migration or a backfill. It also
# self-corrects: Certification::YswsReviewUndoer nils airtable_synced_at, so an
# undone review drops straight out of the total.
#
# The arithmetic mirrors Certification::YswsAirtableSyncJob#build_airtable_fields
# so the bar counts the same hours the base received: each review's
# reviewer-approved devlog minutes, less any fraud deduction on its ship event,
# floored at zero. Reviews the job would have marked rejected (banned user, or
# under the approved-minutes floor) are left out.
#
# To reconcile by hand after the campaign, this is the same sum in SQL:
#
#   SELECT ROUND(SUM(net_minutes) / 60.0, 2) AS hours
#   FROM (
#     SELECT GREATEST(
#              COALESCE(SUM(dr.approved_minutes), 0)
#                - COALESCE(MAX(CASE WHEN ci.status = 3
#                                    THEN ci.deduction_minutes END), 0), 0) AS net_minutes
#     FROM certification_ysws_reviews r
#     JOIN users u ON u.id = r.user_id
#     LEFT JOIN certification_devlog_reviews dr ON dr.ysws_review_id = r.id
#     LEFT JOIN certification_integrities ci ON ci.ship_event_id = r.post_ship_event_id
#     WHERE r.airtable_synced_at BETWEEN '<start>' AND '<end>'
#       AND u.banned = FALSE
#     GROUP BY r.id
#     HAVING COALESCE(SUM(dr.approved_minutes), 0) >= 6
#   ) per_review;
#
module RocketProgress
  GOAL_HOURS = 500

  # Campaign window, in the program's own time zone (reviews and review weeks
  # all run on Eastern wall clock). Only submissions synced inside it count, so
  # these two dates are what "starts at 0" means — set them to the real run.
  WINDOW_START = Certification::Ysws::PROGRAM_ZONE.parse("2026-09-03 00:00").freeze
  WINDOW_END   = Certification::Ysws::PROGRAM_ZONE.parse("2026-09-24 23:59").freeze

  # The sum walks one row per synced review, so it's cached rather than run on
  # every home page render. A few minutes stale is fine for a 500-hour goal.
  CACHE_KEY = "rocket_progress/approved_hours"
  CACHE_TTL = 5.minutes

  # One reading of the goal. Everything a caller needs comes off a single
  # figure, so a render can't mix a fresh total with a stale remainder when the
  # cache expires between two questions.
  Snapshot = Data.define(:hours, :goal_hours) do
    def remaining_hours = [ goal_hours - hours, 0 ].max.round(2)
    def percent = [ (hours / goal_hours.to_f * 100).round, 100 ].min
    def complete? = hours >= goal_hours
  end

  class << self
    def snapshot = Snapshot.new(hours: hours, goal_hours: GOAL_HOURS)

    # Hours banked so far, rounded the way the sync job rounds each submission.
    def hours
      Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { approved_minutes / 60.0 }.round(2)
    end

    private

      def window = WINDOW_START..WINDOW_END

      # Net approved minutes per review, summed. Grouped in the database and
      # totalled here so the CASE/GREATEST arithmetic stays legible.
      def approved_minutes
        Certification::Ysws
          .where(airtable_synced_at: window)
          .joins(:user)
          .where(users: { banned: false })
          .left_joins(:devlog_reviews, :integrity_check)
          .group(:id)
          .having("COALESCE(SUM(certification_devlog_reviews.approved_minutes), 0) >= ?",
                  Certification::Ysws::MIN_APPROVED_MINUTES)
          .pluck(Arel.sql(NET_MINUTES_SQL))
          .sum
      end
  end

  # Reviewer-approved minutes less a fraud deduction on the ship event, floored
  # at zero — Certification::YswsAirtableSyncJob's net_approved_minutes.
  NET_MINUTES_SQL = <<~SQL.squish.freeze
    GREATEST(
      COALESCE(SUM(certification_devlog_reviews.approved_minutes), 0)
        - COALESCE(MAX(CASE WHEN certification_integrities.status = #{Certification::Integrity.statuses[:deducted]}
                            THEN certification_integrities.deduction_minutes END), 0),
      0
    )
  SQL
end
