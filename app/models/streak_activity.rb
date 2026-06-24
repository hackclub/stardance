# == Schema Information
#
# Table name: streak_activities
#
#  id            :bigint           not null, primary key
#  activity_date :date             not null
#  coded_seconds :integer          default(0), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  user_id       :bigint           not null
#
# Indexes
#
#  index_streak_activities_on_user_id                    (user_id)
#  index_streak_activities_on_user_id_and_activity_date  (user_id,activity_date) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class StreakActivity < ApplicationRecord
  DAILY_GOAL_SECONDS = 300 # 5 minutes

  belongs_to :user

  validates :activity_date, presence: true
  validates :activity_date, uniqueness: { scope: :user_id }
  validates :coded_seconds, numericality: { greater_than_or_equal_to: 0 }

  scope :completed, -> { where("coded_seconds >= ?", DAILY_GOAL_SECONDS) }
  scope :for_date, ->(date) { where(activity_date: date) }
  scope :for_range, ->(range) { where(activity_date: range) }

  has_paper_trail

  def completed?
    coded_seconds >= DAILY_GOAL_SECONDS
  end

  class << self
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

      user.update_column(:streak_synced_at, Time.current) if user.has_attribute?(:streak_synced_at)
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
