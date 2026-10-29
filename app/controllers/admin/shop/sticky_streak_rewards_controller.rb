class Admin::Shop::StickyStreakRewardsController < Admin::ApplicationController
  # The day-to-sticker map for the Sticky Streak challenge, one track per run
  # type. Edited as one form so a manager can lay out every day in a single
  # pass; each changed day is still its own PaperTrail version.
  FIRST_RUN_KINDS = %w[first retry].freeze

  def show
    authorize StickyStreakReward

    @shop_items = ShopItem.order(:name)
    @rewards = { "standard" => StickyStreakReward.by_day(:standard),
                 "second" => StickyStreakReward.by_day(:second) }

    first_runs = StickyStreak.where(kind: FIRST_RUN_KINDS).not_superseded
    second_runs = StickyStreak.kind_second
    @day_stats = { "standard" => StickyStreak.day_stats(first_runs),
                   "second" => StickyStreak.day_stats(second_runs) }
    @total_runs = { "standard" => first_runs.count, "second" => second_runs.count }
  end

  def update
    authorize StickyStreakReward

    StickyStreakReward.transaction do
      day_params.each do |track, days|
        days.each { |day, shop_item_id| apply_reward(track, day.to_i, shop_item_id.presence) }
      end
    end

    redirect_to admin_shop_sticky_streak_rewards_path, notice: "Sticky Streak rewards updated."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to admin_shop_sticky_streak_rewards_path, alert: e.record.errors.full_messages.to_sentence
  end

  private

  def apply_reward(track, day, shop_item_id)
    reward = StickyStreakReward.find_by(track: track, day_number: day)

    if shop_item_id.blank?
      reward&.destroy!
    elsif reward
      reward.update!(shop_item_id: shop_item_id)
    else
      StickyStreakReward.create!(track: track, day_number: day, shop_item_id: shop_item_id)
    end
  end

  def day_params
    params.require(:days).permit(
      standard: StickyStreak.reward_days_for(:standard).map(&:to_s),
      second: StickyStreak.reward_days_for(:second).map(&:to_s)
    ).to_h
  end
end
