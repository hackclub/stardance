# == Schema Information
#
# Table name: user_activity_days
#
#  id         :bigint           not null, primary key
#  active_on  :date             not null
#  sources    :string           default([]), not null, is an Array
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_user_activity_days_on_active_on              (active_on)
#  index_user_activity_days_on_user_id_and_active_on  (user_id,active_on) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
# One row per user per day they did something, tagged with what they did.
# It feeds the growth model (GrowthDailySnapshot), which needs to know, for
# every user and every day, whether they were active.
class UserActivityDay < ApplicationRecord
  # Days start at midnight Eastern, the same boundary the signups view uses.
  TIME_ZONE = "America/New_York".freeze
  SOURCES = %w[coding devlog ship vote social shop daily_roll visit].freeze
  # Inserts merge into an existing day, so rebuilding a day never drops a
  # source recorded live (visits) or by an earlier run.
  MERGE_ON_CONFLICT = <<~SQL.freeze
    ON CONFLICT (user_id, active_on) DO UPDATE
    SET sources = ARRAY(SELECT DISTINCT unnest(user_activity_days.sources || EXCLUDED.sources) ORDER BY 1),
        updated_at = NOW()
  SQL

  belongs_to :user

  def self.today = Time.current.in_time_zone(TIME_ZONE).to_date

  # Signed-in page views. The cache key keeps this to one write per user per day.
  def self.track_visit(user_id)
    Rails.cache.fetch("user_activity_day/visit/#{user_id}/#{today}", expires_in: 1.day) do
      merge_sources!([ [ user_id, today, "visit" ] ])
      true
    end
  end

  # Adds each [user_id, date, source] to that user's day, keeping whatever
  # sources the day already had. Rows for users that no longer exist are skipped.
  def self.merge_sources!(rows)
    return if rows.empty?

    user_ids, dates, sources = rows.transpose
    connection.exec_update(sanitize_sql_array([ <<~SQL, user_ids, dates, sources ]))
      INSERT INTO user_activity_days (user_id, active_on, sources, created_at, updated_at)
      SELECT rows.user_id, rows.active_on, array_agg(DISTINCT rows.source ORDER BY rows.source), NOW(), NOW()
      FROM unnest(ARRAY[?]::bigint[], ARRAY[?]::date[], ARRAY[?]::varchar[]) AS rows(user_id, active_on, source)
      JOIN users ON users.id = rows.user_id
      GROUP BY rows.user_id, rows.active_on
      #{MERGE_ON_CONFLICT}
    SQL
  end
end
