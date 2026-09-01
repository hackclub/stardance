# == Schema Information
#
# Table name: streak_activities
#
#  id                   :bigint           not null, primary key
#  activity_date        :date             not null
#  coded_seconds        :integer          default(0), not null
#  manual_credit_at     :datetime
#  manual_credit_reason :string
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  manual_credit_by_id  :bigint
#  user_id              :bigint           not null
#
# Indexes
#
#  index_streak_activities_on_manual_credit_by_id        (manual_credit_by_id)
#  index_streak_activities_on_user_id                    (user_id)
#  index_streak_activities_on_user_id_and_activity_date  (user_id,activity_date) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (manual_credit_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id)
#
class StreakActivity < ApplicationRecord
  DAILY_GOAL_SECONDS = 300 # 5 minutes

  # The months the streak calendar can page through, program start to end.
  CALENDAR_FIRST_MONTH = Date.new(2026, 6, 1)
  CALENDAR_LAST_MONTH = Date.new(2026, 9, 1)

  belongs_to :user
  belongs_to :manual_credit_by, class_name: "User", optional: true

  validates :activity_date, presence: true
  validates :activity_date, uniqueness: { scope: :user_id }
  validates :coded_seconds, numericality: { greater_than_or_equal_to: 0 }
  validates :manual_credit_reason, presence: true, if: :manually_credited?

  scope :completed, -> { where("coded_seconds >= ? OR manual_credit_at IS NOT NULL", DAILY_GOAL_SECONDS) }
  scope :manually_credited, -> { where.not(manual_credit_at: nil) }
  scope :for_date, ->(date) { where(activity_date: date) }
  scope :for_range, ->(range) { where(activity_date: range) }

  has_paper_trail

  def completed?
    coded_seconds >= DAILY_GOAL_SECONDS || manually_credited?
  end

  def manually_credited?
    manual_credit_at.present?
  end

  # Leaves the row behind holding whatever coding time it always had, so
  # revoking a credit granted in error cannot destroy real Hackatime data.
  def revoke_credit!
    update!(manual_credit_at: nil, manual_credit_by: nil, manual_credit_reason: nil)
    user.recalculate_streak!
  end

  class << self
    # Hands someone a day they did not code, for a helper fixing a day
    # Hackatime got wrong. The credit lives beside coded_seconds rather than in
    # it because sync_for_user! rewrites coded_seconds from Hackatime every
    # sync, which would quietly undo the fix.
    #
    # Nothing about a streak is stored, so crediting a missed day repairs it
    # everywhere at once: the run count, the calendar, and a Sticky Streak that
    # had already broken on that day.
    def credit!(user:, date:, granted_by:, reason:)
      activity = find_or_initialize_by(user: user, activity_date: date)
      activity.update!(manual_credit_at: Time.current, manual_credit_by: granted_by, manual_credit_reason: reason)
      user.recalculate_streak!
      activity
    end

    def sync_for_user!(user)
      return nil unless user.hackatime_identity.present?

      linked_projects = user.hackatime_projects.where.not(project_id: nil)
      return nil if linked_projects.empty?

      project_keys = linked_projects.pluck(:name)
      today = streak_date_for(Time.current, user.timezone)

      last_synced = user.try(:streak_synced_at)
      start_date = if last_synced
        streak_date_for(last_synced, user.timezone)
      else
        Date.parse(HackatimeService::START_DATE)
      end

      spans = HackatimeService.fetch_heartbeat_spans(
        user.hackatime_identity.uid,
        project_keys,
        start_date: start_date.to_s,
        end_date: (today + 1.day).to_s,
        access_token: user.hackatime_identity.access_token
      )
      return nil if spans.nil?

      daily_seconds = bucket_spans_by_streak_day(spans, user.timezone)

      (start_date..today).each do |date|
        seconds = daily_seconds.fetch(date, 0)
        record = find_or_initialize_by(user_id: user.id, activity_date: date)
        next if record.persisted? && record.coded_seconds == seconds
        record.update!(coded_seconds: seconds)
      end

      first_sync = last_synced.nil?
      previous_streak = user.current_streak
      user.update_column(:streak_synced_at, Time.current)
      user.recalculate_streak!
      SetSlackStreakStatusJob.perform_later(user.id, previous_streak: previous_streak) unless first_sync
    end

    def streak_date_for(time, timezone)
      tz = timezone.presence || "UTC"
      (time.in_time_zone(tz) - 2.hours).to_date
    end

    private

    def bucket_spans_by_streak_day(spans, timezone)
      tz = timezone.presence || "UTC"
      buckets = Hash.new(0)

      spans.each do |span|
        duration = span["duration"].to_f
        next if duration <= 0

        start_local = Time.at(span["start_time"].to_f).in_time_zone(tz)
        end_local = Time.at(span["end_time"].to_f).in_time_zone(tz)

        start_date = (start_local - 2.hours).to_date
        end_date = (end_local - 2.hours).to_date

        if start_date == end_date
          buckets[start_date] += duration.round
        else
          remaining = duration
          cursor = start_local

          while remaining > 0
            day = (cursor - 2.hours).to_date
            next_day = day + 1.day
            next_boundary = ActiveSupport::TimeZone[tz].local(next_day.year, next_day.month, next_day.day, 2, 0, 0)
            secs = [ next_boundary - cursor, remaining ].min
            buckets[day] += secs.round
            remaining -= secs
            cursor = next_boundary
          end
        end
      end

      buckets
    end
  end
end
