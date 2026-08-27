class Admin::Shop::StickyStreakRewardsController < Admin::ApplicationController
  # The day-to-sticker map for the Sticky Streak challenge. Edited as one form
  # so a manager can lay out all 21 days in a single pass; each changed day is
  # still its own PaperTrail version.
  def show
    authorize StickyStreakReward

    @rewards = StickyStreakReward.by_day
    @shop_items = ShopItem.order(:name)
    @day_stats = StickyStreak.day_stats
    @total_runs = StickyStreak.count
  end

  def update
    authorize StickyStreakReward

    StickyStreakReward.transaction do
      day_params.each { |day, shop_item_id| apply_reward(day.to_i, shop_item_id.presence) }
    end

    redirect_to admin_shop_sticky_streak_rewards_path, notice: "Sticky Streak rewards updated."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to admin_shop_sticky_streak_rewards_path, alert: e.record.errors.full_messages.to_sentence
  end

  private

  def apply_reward(day, shop_item_id)
    reward = StickyStreakReward.find_by(day_number: day)

    if shop_item_id.blank?
      reward&.destroy!
    elsif reward
      reward.update!(shop_item_id: shop_item_id)
    else
      StickyStreakReward.create!(day_number: day, shop_item_id: shop_item_id)
    end
  end

  def day_params
    params.require(:days).permit(*(1..StickyStreak::LENGTH).map(&:to_s)).to_h
  end
end
