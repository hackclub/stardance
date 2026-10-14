# == Schema Information
#
# Table name: growth_daily_snapshots
#
#  id                :bigint           not null, primary key
#  at_risk_mau       :integer          default(0), not null
#  at_risk_wau       :integer          default(0), not null
#  current_users     :integer          default(0), not null
#  dormant_users     :integer          default(0), not null
#  metric            :string           not null
#  new_users         :integer          default(0), not null
#  reactivated_users :integer          default(0), not null
#  resurrected_users :integer          default(0), not null
#  snapshot_on       :date             not null
#  transitions       :jsonb            not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#
# Indexes
#
#  index_growth_daily_snapshots_on_metric_and_snapshot_on  (metric,snapshot_on) UNIQUE
#
# One day of the Duolingo-style growth model for one activity metric: how many
# users sat in each state that day, and how many moved from each state the day
# before into each state today. Built by Growth::SnapshotBuilder.
class GrowthDailySnapshot < ApplicationRecord
  # Each metric is a definition of "active": a user is active on a day if
  # they have any of the metric's sources that day.
  METRICS = {
    "coding" => [ "coding" ],
    "engaged" => UserActivityDay::SOURCES - [ "visit" ],
    **UserActivityDay::SOURCES.index_with { |source| [ source ] }
  }.freeze

  # The DAU we report and project: 5+ minutes of Hackatime coding on a
  # project linked to Stardance. The other metrics are for comparison.
  SOURCE_OF_TRUTH = "coding".freeze

  METRIC_LABELS = {
    "engaged" => "Engaged (any action)",
    "coding" => "Coding (5+ min on Hackatime)",
    "devlog" => "Devlogs",
    "ship" => "Ships",
    "vote" => "Votes",
    "social" => "Likes, comments and reposts",
    "shop" => "Shop orders",
    "daily_roll" => "Daily roll",
    "visit" => "Visited the site"
  }.freeze

  # State => count column. The first four are active on the day.
  STATE_COLUMNS = {
    "new" => :new_users,
    "current" => :current_users,
    "reactivated" => :reactivated_users,
    "resurrected" => :resurrected_users,
    "at_risk_wau" => :at_risk_wau,
    "at_risk_mau" => :at_risk_mau,
    "dormant" => :dormant_users
  }.freeze
  STATES = STATE_COLUMNS.keys.freeze
  ACTIVE_STATES = STATES.first(4).freeze

  # Rate => [state yesterday, state today], as named in Duolingo's model.
  RATES = {
    "nurr" => [ "new", "current" ],
    "curr" => [ "current", "current" ],
    "rurr" => [ "reactivated", "current" ],
    "surr" => [ "resurrected", "current" ],
    "iwaurr" => [ "at_risk_wau", "current" ],
    "reactivation" => [ "at_risk_mau", "reactivated" ],
    "resurrection" => [ "dormant", "resurrected" ],
    "wau_loss" => [ "at_risk_wau", "at_risk_mau" ],
    "mau_loss" => [ "at_risk_mau", "dormant" ]
  }.freeze

  validates :metric, inclusion: { in: METRICS.keys }

  scope :for_metric, ->(metric) { where(metric: metric).order(:snapshot_on) }

  def count_for(state) = public_send(STATE_COLUMNS.fetch(state))

  def dau = ACTIVE_STATES.sum { |state| count_for(state) }
  def wau = dau + at_risk_wau
  def mau = wau + at_risk_mau

  # Users who were in `from` yesterday, or nil if there were none.
  def users_leaving(from) = transitions.fetch(from, {}).values.sum.nonzero?

  def rate(name)
    from, to = RATES.fetch(name)
    total = users_leaving(from)
    total && transitions[from].fetch(to, 0).fdiv(total)
  end
end
