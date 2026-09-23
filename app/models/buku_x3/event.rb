# == Schema Information
#
# Table name: buku_x3_events
#
#  id                  :bigint           not null, primary key
#  destruction_minutes :integer          default(0), not null
#  key                 :string           not null
#  unlocked_at         :datetime
#  visual_intensity    :integer          default(100), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
# Indexes
#
#  index_buku_x3_events_on_key  (key) UNIQUE
#
class BukuX3::Event < ApplicationRecord
  KEY = "bukux3"
  MINUTES_PER_PERCENT = 50 * 60
  MAX_DESTRUCTION_MINUTES = 100 * MINUTES_PER_PERCENT
  STARTING_PERCENT = 25
  STARTING_DESTRUCTION_MINUTES = STARTING_PERCENT * MINUTES_PER_PERCENT
  REPORTING_TIME_ZONE = "America/New_York"

  has_paper_trail
  has_many :contributions, class_name: "BukuX3::Contribution", dependent: :destroy

  # Uniqueness is enforced by the database so create_or_find_by! can safely
  # recover from concurrent first-completion observations.
  validates :key, presence: true
  validates :destruction_minutes, numericality: { only_integer: true, in: 0..MAX_DESTRUCTION_MINUTES }
  validates :visual_intensity, numericality: { only_integer: true, in: 0..200 }

  def self.current = find_by(key: KEY)
  def self.active? = current&.active? || false
  def self.percent = current&.percent || STARTING_PERCENT

  def active?
    unlocked_at.present? && unlocked_at <= Time.current
  end

  def percent
    active? ? (destruction_minutes.to_f / MINUTES_PER_PERCENT).round(4) : STARTING_PERCENT
  end

  def team_hours
    minutes = contributions.group(:buku).sum(:minutes)
    { buku: minutes.fetch(true, 0) / 60.0, bean: minutes.fetch(false, 0) / 60.0 }
  end

  # Attribute late approvals to the original ship day, not the review day.
  # Zeroed contributions (e.g. rejected or deducted ships) do not participate.
  def daily_active_shippers
    today = Time.current.in_time_zone(REPORTING_TIME_ZONE).to_date
    first_day = today - 13
    zone = ActiveSupport::TimeZone[REPORTING_TIME_ZONE]
    day_sql = Arel.sql("(shipped_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/New_York')::date")
    counts = contributions.where("minutes > 0")
      .where(shipped_at: zone.local(first_day.year, first_day.month, first_day.day)...zone.local(today.year, today.month, today.day).tomorrow)
      .group(day_sql, :buku).distinct.count(:user_id)

    (first_day..today).to_a.reverse.map do |date|
      { date: date, buku: counts.fetch([ date, true ], 0), bean: counts.fetch([ date, false ], 0) }
    end
  end
end
