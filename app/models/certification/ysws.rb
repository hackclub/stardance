# == Schema Information
#
# Table name: certification_ysws_reviews
#
#  id                    :bigint           not null, primary key
#  airtable_synced_at    :datetime
#  approved_minutes      :integer
#  claimed_at            :datetime
#  demo_checked_at       :datetime
#  in_unified_db         :string
#  original_minutes      :integer
#  repo_checked_at       :datetime
#  returned_at           :datetime
#  reviewed_at           :datetime
#  spotchecked_at        :datetime
#  summary_justification :text
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  claimed_by_id         :bigint
#  post_ship_event_id    :bigint           not null
#  project_id            :bigint           not null
#  reviewer_id           :bigint
#  ship_cert_id          :bigint
#  spotchecked_by_id     :bigint
#  user_id               :bigint           not null
#
# Indexes
#
#  index_certification_ysws_reviews_on_claimed_by_id       (claimed_by_id)
#  index_certification_ysws_reviews_on_post_ship_event_id  (post_ship_event_id)
#  index_certification_ysws_reviews_on_project_id          (project_id)
#  index_certification_ysws_reviews_on_reviewer_id         (reviewer_id)
#  index_certification_ysws_reviews_on_ship_cert_id        (ship_cert_id)
#  index_certification_ysws_reviews_on_spotchecked_by_id   (spotchecked_by_id)
#  index_certification_ysws_reviews_on_user_id             (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (claimed_by_id => users.id)
#  fk_rails_...  (post_ship_event_id => post_ship_events.id)
#  fk_rails_...  (project_id => projects.id)
#  fk_rails_...  (reviewer_id => users.id)
#  fk_rails_...  (ship_cert_id => certification_ship_reviews.id)
#  fk_rails_...  (spotchecked_by_id => users.id)
#  fk_rails_...  (user_id => users.id)
#
module Certification
  class Ysws < ApplicationRecord
    self.table_name = "certification_ysws_reviews"

    has_paper_trail

    belongs_to :reviewer, class_name: "User", optional: true
    belongs_to :user
    belongs_to :project, -> { with_deleted }, optional: true
    belongs_to :ship_cert, class_name: "Certification::Ship", optional: true
    belongs_to :post_ship_event, class_name: "Post::ShipEvent"
    belongs_to :spotchecked_by, class_name: "User", optional: true
    belongs_to :claimed_by, class_name: "User", optional: true

    has_many :devlog_reviews, class_name: "Certification::Devlog", foreign_key: :ysws_review_id, dependent: :destroy

    # An integrity check hangs off the ship event (one per ship event), so a
    # review maps 1-1 to one through its own ship event.
    has_one :integrity_check, through: :post_ship_event, source: :integrity_check
    has_one :mac_analysis, class_name: "Certification::MACAnalysis",
                           foreign_key: :ysws_review_id,
                           dependent: :destroy

    validates :original_minutes, numericality: { greater_than_or_equal_to: 0 }, allow_nil: false
    validates :approved_minutes, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

    MIN_APPROVED_MINUTES = 6

    # How long a reviewer's claim on a review holds before it's up for grabs
    # again. There's no separate expiry column — expiry is just claimed_at + TTL.
    CLAIM_TTL = 20.minutes

    # ---- Review-queue scopes ---------------------------------------------

    scope :pending, -> { where(reviewed_at: nil, returned_at: nil) }
    scope :without_mac_analysis, -> { left_joins(:mac_analysis).where(certification_mac_analyses: { id: nil }) }

    # A review is visible to a reviewer if nobody holds an active claim on it,
    # or they're the one holding it.
    scope :unclaimed_or_claimed_by, ->(user) {
      where("certification_ysws_reviews.claimed_by_id IS NULL OR certification_ysws_reviews.claimed_at IS NULL OR certification_ysws_reviews.claimed_at < :expired OR certification_ysws_reviews.claimed_by_id = :user_id",
            expired: CLAIM_TTL.ago, user_id: user.id)
    }

    # Correlated subquery counting a review's still-pending child devlog
    # reviews — the "todo" work left on it. Reused by the count select and the
    # "todo" column sort so they stay in sync.
    TODO_DEVLOG_COUNT_SQL = <<~SQL.squish.freeze
      (SELECT COUNT(*) FROM certification_devlog_reviews
        WHERE certification_devlog_reviews.ysws_review_id = certification_ysws_reviews.id
          AND certification_devlog_reviews.status = 'pending')
    SQL

    # Exposes a `todo_devlog_count` attribute on each loaded record without an
    # N+1 — read it via #todo_devlog_count.
    scope :with_todo_devlog_count, -> {
      select("certification_ysws_reviews.*", "#{TODO_DEVLOG_COUNT_SQL} AS todo_devlog_count")
    }

    # Reviews whose ship event already carries a decided integrity check, or
    # whose project is hardware (hardware projects skip integrity checks).
    scope :with_integrity_check, -> {
      hardware = joins(:project).where.not(projects: { hardware_stage: nil })
      decided  = joins(:integrity_check).where.not(certification_integrities: { status: :pending })
      where(id: hardware).or(where(id: decided))
    }

    scope :by_project_type, ->(type) {
      type == "unclassified" \
        ? joins(:project).where(projects: { project_type: nil })
        : joins(:project).where(projects: { project_type: type })
    }

    # Project reviews completed from `time` onwards, with a reviewer attached — the
    # shared base for every per-reviewer project count. Reviews auto-rejected before
    # anyone claimed them carry no reviewer_id and must not be credited to a row.
    scope :completed_since, ->(time) { where(reviewed_at: time..).where.not(reviewer_id: nil) }

    # Claims (or refreshes an existing claim on) a pending review for the
    # given user, unless someone else already holds an active claim on it.
    # Conditioned atomically in the UPDATE itself so two reviewers opening the
    # same review at once can't both win the claim. Returns the claimed
    # record, or nil if another reviewer's claim is still active.
    def self.atomic_claim!(record_id, user)
      now = Time.current
      updated = pending.where(id: record_id)
        .where("claimed_by_id IS NULL OR claimed_at IS NULL OR claimed_at < :expired OR claimed_by_id = :user_id",
               expired: CLAIM_TTL.ago, user_id: user.id)
        .update_all(claimed_by_id: user.id, claimed_at: now, updated_at: now)
      updated.zero? ? nil : find(record_id)
    end

    # Count of still-pending child devlog reviews. Available only on records
    # loaded through .with_todo_devlog_count.
    def todo_devlog_count
      self[:todo_devlog_count].to_i
    end

    # The ship certification a reviewer should actually look at for this review.
    #
    # ship_cert_id is only populated when the ship event went through manual
    # ship certification. Reships auto-approve off a passing URL probe and never
    # mint a cert, so the column stays null even though the project was
    # certified on an earlier ship. Fall back the same way #return_to_ship_cert
    # does — match the ship event first, then the project's most recent approved
    # cert — so reship reviews still point somewhere real.
    def effective_ship_cert
      return ship_cert if ship_cert

      project_certs = Certification::Ship.where(project_id: project_id)
      project_certs.find_by(post_ship_event_id: post_ship_event_id) ||
        project_certs.approved.order(Arel.sql("decided_at DESC NULLS LAST"), id: :desc).first
    end

    # Per-reviewer target for completed devlog reviews: a daily rate that
    # reviewers are expected to average across the review week, rather than hit
    # every single day. Drives the pace widget on the review queue.
    DEVLOG_REVIEW_GOAL_PER_DAY = 30

    # Length of a review week, and the devlog total a reviewer has to reach
    # across it to take their week's payout in full rather than halved.
    REVIEW_WEEK_DAYS = 7
    WEEKLY_DEVLOG_GOAL = DEVLOG_REVIEW_GOAL_PER_DAY * REVIEW_WEEK_DAYS

    # The second path to locked-in status: a reviewer averaging this many completed
    # project reviews a day across the review week is locked in whatever their
    # devlog count, and vice versa. Deliberately the same shape as
    # DEVLOG_REVIEW_GOAL_PER_DAY so the two paths read alike everywhere.
    PROJECT_REVIEW_GOAL_PER_DAY = 20
    WEEKLY_PROJECT_GOAL = PROJECT_REVIEW_GOAL_PER_DAY * REVIEW_WEEK_DAYS

    # Rolling window the reviewer leaderboard ranks on. Deliberately independent
    # of the review week: it's always this full span, so a reviewer's standing
    # doesn't reset to zero every Wednesday 4pm.
    LEADERBOARD_WINDOW = 3.days

    # Metrics the leaderboard can rank on — one per locked-in path — and the one an
    # absent or unrecognised choice falls back to.
    LEADERBOARD_METRICS = %w[devlogs projects].freeze
    DEFAULT_LEADERBOARD_METRIC = "devlogs"

    # Program-facing time zone. The app's default zone is UTC, but reviewers,
    # review weeks and bonus windows all run on Eastern wall-clock time.
    PROGRAM_ZONE = Time.find_zone!("America/New_York")

    # Review weeks run Wednesday 4pm to the following Wednesday 4pm, Eastern.
    REVIEW_WEEK_START_DAY = :wednesday
    REVIEW_WEEK_START_HOUR = 16

    # Projected stardust per reviewed devlog, tiered by the reviewer's running
    # devlog-review count: a reviewer's Nth devlog pays the rate for the tier N
    # falls in. YSWS reviewing isn't a real payout source yet (no
    # stardust_earned column), so this drives the dashboard leaderboard's
    # projected payout only.
    #
    # Each entry is [threshold, rate]: devlogs *after* `threshold` (up to the
    # next threshold) pay `rate`.
    #   1..900     => 0.2
    #   901..1500  => 0.3
    #   1501..2100 => 0.35
    #   2101..     => 0.4
    DEVLOG_STARDUST_TIERS = [
      [ 0,    0.2  ],
      [ 900,  0.3  ],
      [ 1500, 0.35 ],
      [ 2100, 0.4  ]
    ].freeze

    # Limited-time bonuses. Each entry is [window, extra_per_devlog]: devlogs
    # whose parent review completed within `window` earn that much extra
    # stardust *on top of* their tier rate (additive, so a reviewer never loses
    # their higher tier rate for reviewing during a window). Windows are
    # non-overlapping and expressed in PROGRAM_ZONE so EDT offsets apply
    # correctly regardless of the app's default zone.
    BONUS_WINDOWS = [
      # 11am EDT July 9 2026 → 4pm EDT July 13 2026.
      [ PROGRAM_ZONE.local(2026, 7, 9, 11, 0)..PROGRAM_ZONE.local(2026, 7, 13, 16, 0), 0.1 ],
      # 4:15pm EDT July 24 2026 → 4:15pm EDT July 27 2026 (Mon).
      [ PROGRAM_ZONE.local(2026, 7, 24, 16, 15)..PROGRAM_ZONE.local(2026, 7, 27, 16, 15), 0.05 ]
    ].freeze

    # SQL expression yielding the per-devlog bonus stardust for a review, based
    # on which BONUS_WINDOWS entry (if any) its reviewed_at falls in.
    def self.bonus_stardust_case_sql
      whens = BONUS_WINDOWS.map do |window, per_devlog|
        sanitize_sql_array([
          "WHEN certification_ysws_reviews.reviewed_at BETWEEN ? AND ? THEN ?",
          window.begin, window.end, per_devlog
        ])
      end
      "CASE #{whens.join(' ')} ELSE 0 END"
    end

    # Projected stardust for a reviewer who has completed `count` devlog
    # reviews, applying DEVLOG_STARDUST_TIERS cumulatively across the tiers.
    def self.stardust_for_devlog_count(count)
      DEVLOG_STARDUST_TIERS.each_with_index.sum do |(threshold, rate), i|
        upper   = DEVLOG_STARDUST_TIERS[i + 1]&.first || Float::INFINITY
        in_tier = [ count, upper ].min - threshold
        in_tier.positive? ? in_tier * rate : 0
      end.round(2)
    end

    # The DEVLOG_STARDUST_TIERS entry a reviewer on `count` lifetime devlogs is
    # working toward, or nil once they're on the top tier. Mirrors
    # Certification::Ship.next_milestone so both reviewer surfaces read alike.
    #   => { threshold:, rate:, current_rate:, devlogs_needed:, percent: }
    def self.next_stardust_tier(count)
      # The first tier's threshold is 0, so a non-negative count always sits at
      # or past it — index is never 0 and the tier below always exists.
      index = DEVLOG_STARDUST_TIERS.index { |threshold, _rate| threshold > count }
      return nil if index.nil?

      threshold, rate = DEVLOG_STARDUST_TIERS[index]
      floor           = DEVLOG_STARDUST_TIERS[index - 1].first

      {
        threshold: threshold,
        rate: rate,
        current_rate: stardust_rate_for(count),
        devlogs_needed: threshold - count,
        # Progress through the current tier's own span, so a reviewer who just
        # crossed into a tier starts near empty rather than three-quarters full.
        percent: ((count - floor) / (threshold - floor).to_f * 100).clamp(0, 100).round
      }
    end

    # Devlog-review leaderboard for the trailing LEADERBOARD_WINDOW. A devlog
    # counts as reviewed once its parent YSWS review is completed (reviewed_at
    # present); completion already forces every child devlog out of :pending.
    #
    # `devlogs` — and the ranking — cover only the window, and reviewers with
    # nothing in it are left off entirely. `stardust` stays all-time projected
    # payout: it scales with each reviewer's lifetime total via the
    # DEVLOG_STARDUST_TIERS rate tiers, plus the per-devlog bonus for any devlogs
    # reviewed within a BONUS_WINDOWS window.
    # `reviews` counts the distinct YSWS reviews completed in the same window —
    # one per ship review, however many devlogs it covered.
    #   => [{ reviewer_id:, name:, devlogs:, reviews:, stardust: }, ...] desc by devlogs
    def self.reviewer_devlog_leaderboard(now: Time.current)
      window_start = now - LEADERBOARD_WINDOW

      windowed_counts = Certification::Devlog
        .joins(:ysws_review)
        .where(certification_ysws_reviews: { reviewed_at: window_start.. })
        .where.not(certification_ysws_reviews: { reviewer_id: nil })
        .group("certification_ysws_reviews.reviewer_id")
        .count

      return [] if windowed_counts.empty?

      windowed_review_counts = where(reviewed_at: window_start..)
        .where(reviewer_id: windowed_counts.keys)
        .group(:reviewer_id)
        .count

      bonus_case = bonus_stardust_case_sql

      # All-time counts for the ranked reviewers, split by their per-devlog bonus
      # amount, so tier rates apply to the lifetime total while each bonus applies
      # only to the devlogs reviewed in its window.
      Certification::Devlog
        .joins(ysws_review: :reviewer)
        .where.not(certification_ysws_reviews: { reviewed_at: nil })
        .where(certification_ysws_reviews: { reviewer_id: windowed_counts.keys })
        .group("users.id", "users.display_name", Arel.sql(bonus_case))
        .count
        .group_by { |(reviewer_id, name, _bonus), _count| [ reviewer_id, name ] }
        .map do |(reviewer_id, name), entries|
          all_time_devlogs = entries.sum { |_key, count| count }
          bonus_stardust   = entries.sum { |(_id, _name, bonus), count| bonus.to_f * count }
          stardust         = (stardust_for_devlog_count(all_time_devlogs) + bonus_stardust).round(2)
          {
            reviewer_id: reviewer_id,
            name: name,
            devlogs: windowed_counts[reviewer_id],
            reviews: windowed_review_counts.fetch(reviewer_id, 0),
            stardust: stardust
          }
        end
        .sort_by { |row| [ -row[:devlogs], row[:name].to_s ] }
    end

    # Devlog reviews credited to a reviewer, applying the counting rule the whole
    # model shares: a devlog counts as reviewed once its parent YSWS review is
    # completed (reviewed_at present), not by the child's own status.
    def self.reviewed_devlogs_for(reviewer_id)
      Certification::Devlog
        .joins(:ysws_review)
        .where.not(certification_ysws_reviews: { reviewed_at: nil })
        .where(certification_ysws_reviews: { reviewer_id: reviewer_id })
    end

    # All-time count of devlogs a given reviewer has reviewed, matching the
    # leaderboard's definition.
    def self.reviewer_devlog_count(reviewer_id, since: nil)
      scope = reviewed_devlogs_for(reviewer_id)
      scope = scope.where(certification_ysws_reviews: { reviewed_at: since.. }) if since
      scope.count
    end

    # Start of the review week containing `now`: the most recent Wednesday 4pm
    # Eastern. `beginning_of_week` lands on that Wednesday at midnight, so the
    # 4pm cutoff can still be in the future — when it is, the week started a
    # week earlier.
    def self.review_week_start(now = Time.current)
      cutoff = now.in_time_zone(PROGRAM_ZONE)
        .beginning_of_week(REVIEW_WEEK_START_DAY)
        .change(hour: REVIEW_WEEK_START_HOUR)
      cutoff <= now ? cutoff : cutoff - 1.week
    end

    # Start of the review day containing `now`. Days run on the same 4pm Eastern
    # boundary as the review week itself, so "today" means one thing to the daily
    # goals, the leaderboard's projects-today column and the progress panel alike.
    def self.review_day_start(now = Time.current)
      local = now.in_time_zone(PROGRAM_ZONE)
      date  = local.hour < REVIEW_WEEK_START_HOUR ? local.to_date - 1 : local.to_date

      PROGRAM_ZONE.local(date.year, date.month, date.day, REVIEW_WEEK_START_HOUR)
    end

    # 1-based day within the review week containing `now`. Days run on the same
    # 4pm boundary as the week itself, so this is 1 on the first 4pm-to-4pm day
    # and 7 on the last.
    #
    # Each 4pm-to-4pm day is keyed by the calendar date it started on, keeping
    # the count wall-clock exact across DST — dividing elapsed seconds by 24h
    # would report an 8th day in the week the clocks fall back, and shift every
    # boundary by an hour in the week they spring forward.
    def self.review_week_day_number(now = Time.current)
      day_start = review_day_start(now).to_date

      (day_start - review_week_start(now).to_date).to_i.clamp(0, REVIEW_WEEK_DAYS - 1) + 1
    end

    # A reviewer's pace against the daily goal for the current review week.
    #
    # `needed_today` is the catch-up figure: how many more devlogs would bring the
    # week's running average up to the daily goal by the end of today. A reviewer
    # who fell behind yesterday owes that shortfall on top of today's quota.
    def self.reviewer_devlog_pace(reviewer_id, now: Time.current)
      day_number = review_week_day_number(now)
      reviewed   = reviewer_devlog_count(reviewer_id, since: review_week_start(now))

      {
        reviewed: reviewed,
        day_number: day_number,
        daily_average: reviewed / day_number.to_f,
        needed_today: [ (DEVLOG_REVIEW_GOAL_PER_DAY * day_number) - reviewed, 0 ].max
      }
    end

    # Devlogs each reviewer has reviewed so far this review week, in one query.
    # The single definition of "this week's work" — `reviewer_daily_averages`
    # divides it by the day number, the progress panel ranks on it directly.
    #   => { reviewer_id => count, ... }
    def self.reviewer_weekly_devlog_counts(now: Time.current)
      Certification::Devlog
        .joins(:ysws_review)
        .where(certification_ysws_reviews: { reviewed_at: review_week_start(now).. })
        .where.not(certification_ysws_reviews: { reviewer_id: nil })
        .group("certification_ysws_reviews.reviewer_id")
        .count
    end

    # Every reviewer's devlogs-per-day for the current review week — the same
    # figure `reviewer_devlog_pace` reports as `daily_average`, for all reviewers
    # in one query so the leaderboard doesn't need one per row.
    #   => { reviewer_id => average, ... }
    def self.reviewer_daily_averages(now: Time.current)
      day_number = review_week_day_number(now)

      reviewer_weekly_devlog_counts(now: now)
        .transform_values { |reviewed| reviewed / day_number.to_f }
    end

    # Reviewer ids already meeting the daily goal averaged across the review week
    # so far — the same bar `reviewer_devlog_pace` reports as "on pace". Returned
    # as a Set so the leaderboard can mark rows without a query per row. Callers
    # that already hold the averages pass them in to avoid a second query.
    def self.reviewers_on_pace(now: Time.current, daily_averages: reviewer_daily_averages(now: now))
      daily_averages
        .select { |_reviewer_id, average| average >= DEVLOG_REVIEW_GOAL_PER_DAY }
        .keys
        .to_set
    end

    # ---- Project-review pace ---------------------------------------------
    #
    # The second locked-in path, mirroring the devlog helpers above one for one so
    # the two read alike wherever they sit side by side. A project counts as
    # reviewed once its own reviewed_at is stamped, so these read straight off this
    # table and need no join.

    # Completed project reviews credited to a reviewer, optionally only those from
    # `since` onwards.
    def self.reviewer_project_count(reviewer_id, since: nil)
      scope = where(reviewer_id: reviewer_id).where.not(reviewed_at: nil)
      scope = scope.where(reviewed_at: since..) if since
      scope.count
    end

    # Projects each reviewer has completed so far this review week, in one query.
    #   => { reviewer_id => count, ... }
    def self.reviewer_weekly_project_counts(now: Time.current)
      completed_since(review_week_start(now)).group(:reviewer_id).count
    end

    # Projects each reviewer has completed so far today, in one query.
    #   => { reviewer_id => count, ... }
    def self.reviewer_project_counts_today(now: Time.current)
      completed_since(review_day_start(now)).group(:reviewer_id).count
    end

    # Every reviewer's projects-per-day for the current review week — the figure
    # `reviewer_project_pace` reports as `daily_average`, for all reviewers at once
    # so the leaderboard doesn't need a query per row.
    #   => { reviewer_id => average, ... }
    def self.reviewer_project_daily_averages(now: Time.current)
      day_number = review_week_day_number(now)

      reviewer_weekly_project_counts(now: now)
        .transform_values { |reviewed| reviewed / day_number.to_f }
    end

    # A reviewer's pace against the daily project goal. Shaped exactly like
    # `reviewer_devlog_pace` — including `needed_today` as the catch-up figure — so
    # `locked_in?` can read either without caring which it was handed.
    def self.reviewer_project_pace(reviewer_id, now: Time.current)
      day_number = review_week_day_number(now)
      reviewed   = reviewer_project_count(reviewer_id, since: review_week_start(now))

      {
        reviewed: reviewed,
        day_number: day_number,
        daily_average: reviewed / day_number.to_f,
        needed_today: [ (PROJECT_REVIEW_GOAL_PER_DAY * day_number) - reviewed, 0 ].max
      }
    end

    # Projects a reviewer has completed since today's 4pm boundary.
    def self.reviewer_projects_today(reviewer_id, now: Time.current)
      reviewer_project_count(reviewer_id, since: review_day_start(now))
    end

    # ---- Locked in -------------------------------------------------------
    #
    # A reviewer is locked in once they clear EITHER daily goal on the review week's
    # running average: DEVLOG_REVIEW_GOAL_PER_DAY devlogs or
    # PROJECT_REVIEW_GOAL_PER_DAY projects. The paths are equivalent and holding one
    # is enough.

    def self.locked_in?(devlog_pace:, project_pace:)
      devlog_pace[:needed_today].zero? || project_pace[:needed_today].zero?
    end

    # Reviewer ids clearing either goal this review week, as a Set so the
    # leaderboard can mark rows without a query per row. Callers that already hold
    # the averages pass them in to avoid re-querying.
    def self.reviewers_locked_in(now: Time.current,
                                 daily_averages: reviewer_daily_averages(now: now),
                                 project_daily_averages: reviewer_project_daily_averages(now: now))
      reviewers_on_pace(now: now, daily_averages: daily_averages) |
        project_daily_averages
          .select { |_reviewer_id, average| average >= PROJECT_REVIEW_GOAL_PER_DAY }
          .keys
    end

    # Devlogs reviewed per reviewer per day over the trailing window, bucketed by
    # the parent review's reviewed_at. Shape is the contract the chart relies on:
    #   => { labels: ["6/1", ...], series: [{ name:, data: [n, ...] }, ...] }
    def self.reviewer_daily_devlog_data(days: 30, now: Time.current)
      start = (now.to_date - (days - 1)).to_time.beginning_of_day

      rows = Certification::Devlog
        .joins(ysws_review: :reviewer)
        .where(certification_ysws_reviews: { reviewed_at: start.. })
        .group("users.id", "users.display_name", Arel.sql("DATE(certification_ysws_reviews.reviewed_at)"))
        .count

      dates  = (0...days).map { |i| now.to_date - (days - 1 - i) }
      labels = dates.map { |d| d.strftime("%-m/%-d") }

      series = rows
        .group_by { |(reviewer_id, name, _day), _count| [ reviewer_id, name ] }
        .sort_by { |_key, entries| -entries.sum { |_key, count| count } }
        .map do |(_reviewer_id, name), entries|
          per_day = entries.to_h { |(_id, _name, day), count| [ day.to_date, count ] }
          { name: name, data: dates.map { |d| per_day[d].to_i } }
        end

      { labels: labels, series: series }
    end

    # reviewed_at as a calendar date in the program's zone. The column is a
    # timestamp without zone holding UTC, so it has to be labelled UTC before it
    # can be converted — a bare `AT TIME ZONE` would read it as Eastern already
    # and shift every date by the offset.
    REVIEWED_LOCAL_DATE_SQL = <<~SQL.squish.freeze
      (certification_ysws_reviews.reviewed_at AT TIME ZONE 'UTC'
        AT TIME ZONE '#{PROGRAM_ZONE.tzinfo.name}')::date
    SQL

    # Devlogs a reviewer reviewed on each program-zone calendar day.
    #   => { Date => count, ... }
    def self.reviewer_devlogs_by_day(reviewer_id)
      reviewed_devlogs_for(reviewer_id)
        .group(Arel.sql(REVIEWED_LOCAL_DATE_SQL))
        .count
        .transform_keys(&:to_date)
    end

    # Consecutive days ending today with at least one devlog reviewed. Today only
    # anchors the streak once there's work on it, so a morning before the first
    # review of the day doesn't read as a break.
    def self.reviewer_streak(devlogs_by_day, now: Time.current)
      day = now.in_time_zone(PROGRAM_ZONE).to_date
      day -= 1 unless devlogs_by_day.key?(day)

      streak = 0
      while devlogs_by_day.key?(day)
        streak += 1
        day -= 1
      end
      streak
    end

    # Everything the reviewer progress panel shows for one reviewer: their pace
    # against the daily goal, what their reviewing adds up to all-time, their
    # momentum, and where they stand in the crew this review week.
    #
    # Deliberately no approval/rejection rate: shown as a number to improve, it
    # rewards rubber-stamping.
    def self.reviewer_progress(reviewer_id, now: Time.current)
      pace           = reviewer_devlog_pace(reviewer_id, now: now)
      weekly_counts  = reviewer_weekly_devlog_counts(now: now)
      devlogs_by_day = reviewer_devlogs_by_day(reviewer_id)

      crew_weekly = weekly_counts.values.sum
      my_weekly   = weekly_counts.fetch(reviewer_id, 0)
      # Ranked only among reviewers who did something this week — matching the
      # leaderboard, which leaves an empty window off entirely.
      ranking = weekly_counts.sort_by { |_id, count| -count }.map(&:first)

      lifetime_devlogs, approved_minutes, people = reviewed_devlogs_for(reviewer_id)
        .pick(Arel.sql(<<~SQL.squish))
          COUNT(*),
          COALESCE(SUM(certification_devlog_reviews.approved_minutes), 0),
          COUNT(DISTINCT certification_ysws_reviews.user_id)
        SQL

      best_day, best_day_devlogs = devlogs_by_day.max_by { |day, count| [ count, day ] }

      {
        pace: pace,
        on_pace: pace[:needed_today].zero?,
        lifetime_devlogs: lifetime_devlogs,
        hours_certified: (approved_minutes / 60.0).round,
        # Distinct people, not projects — one maker with three reviewed projects
        # counts once.
        people_reviewed: people,
        streak: reviewer_streak(devlogs_by_day, now: now),
        best_day: best_day,
        best_day_devlogs: best_day_devlogs,
        weekly_devlogs: my_weekly,
        share_of_week: crew_weekly.zero? ? 0.0 : (my_weekly / crew_weekly.to_f * 100),
        rank: ranking.index(reviewer_id)&.succ,
        crew_size: ranking.size,
        next_tier: next_stardust_tier(lifetime_devlogs)
      }
    end

    def pending?
      reviewed_at.nil? && returned_at.nil?
    end

    def claim_active?
      claimed_by_id.present? && claimed_at.present? && claimed_at > CLAIM_TTL.ago
    end

    def claimed_by?(user)
      claim_active? && claimed_by_id == user.id
    end

    def release_claim!
      return false unless pending? && claim_active?

      update!(claimed_by: nil, claimed_at: nil)
    end

    def approved_minutes_total
      devlog_reviews.sum { |dr| dr.approved_minutes.to_i }
    end

    def review_rejected?
      user.banned? || approved_minutes_total < MIN_APPROVED_MINUTES
    end

    def review_status
      return :in_unified_db if in_unified_db.present?
      return :returned if returned_at.present?
      return :pending unless reviewed_at.present?

      review_rejected? ? :rejected : :approved
    end

    def check_and_update_unified_db_status!
      record = ::Certification::YswsAirtable.record_for(id)
      unified_record_id = record&.[]("Automation - YSWS Record ID").presence

      update_column(:in_unified_db, unified_record_id) if unified_record_id.present? && in_unified_db != unified_record_id
    rescue Faraday::Error => e
      Rails.logger.warn "[Certification::Ysws] Could not check unified DB status for ##{id}: #{e.message}"
    end
  end
end
