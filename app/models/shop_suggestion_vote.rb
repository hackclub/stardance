# == Schema Information
#
# Table name: shop_suggestion_votes
#
#  id                 :bigint           not null, primary key
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  shop_suggestion_id :bigint           not null
#  user_id            :bigint           not null
#
# Indexes
#
#  index_shop_suggestion_votes_on_shop_suggestion_id  (shop_suggestion_id)
#  index_shop_suggestion_votes_on_user_id             (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (shop_suggestion_id => shop_suggestions.id)
#  fk_rails_...  (user_id => users.id)
#
class ShopSuggestionVote < ApplicationRecord
  include Ledgerable

  belongs_to :user
  belongs_to :shop_suggestion

  VOTE_COST = 5
  DAILY_LIMIT = 5
  DAILY_PER_SUGGESTION_LIMIT = 1

  validate :sufficient_balance, on: :create
  validate :daily_vote_budget, on: :create
  validate :one_per_suggestion_per_day, on: :create
  validate :suggestion_is_pending, on: :create

  after_create :charge_vote_fee

  private

  def charge_vote_fee
    LedgerEntry.create!(
      user: user,
      ledgerable: self,
      amount: -VOTE_COST,
      reason: "Shop suggestion vote"
    )
  end

  def sufficient_balance
    return unless user
    return if user.balance >= VOTE_COST

    errors.add(:base, "You need at least #{VOTE_COST} Stardust to vote (you have #{user.balance})")
  end

  def daily_vote_budget
    return unless user

    count = user.shop_suggestion_votes.where(created_at: Time.current.beginning_of_day..).count
    errors.add(:base, "You can only cast #{DAILY_LIMIT} votes per day") if count >= DAILY_LIMIT
  end

  def one_per_suggestion_per_day
    return unless user && shop_suggestion

    count = user.shop_suggestion_votes.where(
      shop_suggestion: shop_suggestion,
      created_at: Time.current.beginning_of_day..
    ).count
    errors.add(:base, "You can only vote for this suggestion once per day") if count >= DAILY_PER_SUGGESTION_LIMIT
  end

  def suggestion_is_pending
    return unless shop_suggestion

    unless shop_suggestion.pending? && !shop_suggestion.discarded?
      errors.add(:base, "This suggestion is no longer accepting votes")
    end
  end
end
