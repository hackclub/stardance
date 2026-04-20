# == Schema Information
#
# Table name: ledger_entries
#
#  id              :bigint           not null, primary key
#  amount          :integer
#  created_by      :string
#  ledgerable_type :string           not null
#  reason          :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  ledgerable_id   :bigint           not null
#  user_id         :bigint           not null
#
# Indexes
#
#  index_ledger_entries_on_ledgerable  (ledgerable_type,ledgerable_id)
#  index_ledger_entries_on_user_id     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class LedgerEntry < ApplicationRecord
  belongs_to :ledgerable, polymorphic: true
  belongs_to :user

  validates :user, presence: true

  before_validation :set_user_from_ledgerable
  before_update :prevent_update
  before_destroy :prevent_destruction

  after_create :create_audit_log
  after_create :notify_balance_change
  after_create :invalidate_user_balance_cache

  private

  def set_user_from_ledgerable
    self.user ||= ledgerable.try(:user)
  end

  def prevent_update
    immutable_attrs = %w[amount user_id ledgerable_id ledgerable_type]
    return unless (changes.keys & immutable_attrs).any?

    raise ActiveRecord::RecordNotSaved, "HEY! Ledger entry amount, user, and ledgerable are immutable. Please create a new offsetting entry instead."
  end

  def prevent_destruction
    return if ledgerable.nil? || ledgerable.destroyed?

    raise ActiveRecord::RecordNotDestroyed, "HEY! Ledger entries are immutable and cannot be destroyed. Please create a new offsetting entry instead. we BLOCKCHAIN in this mf!"
  end

  def create_audit_log
    return unless ledgerable_type == "User"

    new_balance = ledgerable.balance

    PaperTrail::Version.create!(
      item_type: "User",
      item_id: ledgerable.id,
      event: "balance_adjustment",
      whodunnit: PaperTrail.request.whodunnit || created_by&.match(/\((\d+)\)$/)&.captures&.first,
      object_changes: { balance: [ new_balance - amount, new_balance ], reason: reason, created_by: created_by }.to_json
    )
  end

  def notify_balance_change
    return unless user.slack_balance_notifications?

    source = case ledgerable_type
    when "ShopOrder" then "shop purchase"
    when "Post::ShipEvent" then "ship event payout"
    when "User" then "user grant"
    when "User::Achievement" then "achievement: #{ledgerable.achievement.name}"
    when "FulfillmentPayoutLine" then "fulfillment payout"
    when "ShowAndTellAttendance" then "show and tell payout"
    else ledgerable_type.underscore.humanize.downcase
    end
    change_emoji = amount.positive? ? "📈" : "📉"
    message = "#{change_emoji} Balance #{amount.positive? ? '+' : ''}#{amount} 🍪 (#{source}) → #{user.balance} 🍪"

    SendSlackDmJob.perform_later(user.slack_id, message)
    SendSlackDmJob.perform_later("C0A3JN1CMNE", "<@#{user.slack_id}>: #{message}")
  end

  def invalidate_user_balance_cache = user.invalidate_balance_cache!
end
