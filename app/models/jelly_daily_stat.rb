# == Schema Information
#
# Table name: jelly_daily_stats
#
#  id                            :bigint           not null, primary key
#  arrivals                      :integer
#  awaiting_reply_count          :integer
#  median_first_response_seconds :integer
#  open_count                    :integer
#  p95_hang_seconds              :integer
#  recorded_on                   :date             not null
#  resolutions                   :integer
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#
# Indexes
#
#  index_jelly_daily_stats_on_recorded_on  (recorded_on) UNIQUE
#
class JellyDailyStat < ApplicationRecord
  # Jelly has no historical endpoint, so a day's numbers only exist if we
  # recorded them at the time. This table is the history.
  scope :since, ->(date) { where(recorded_on: date..).order(:recorded_on) }

  def self.record_for!(date, attributes)
    stat = find_or_initialize_by(recorded_on: date)
    stat.update!(attributes)
    stat
  end
end
