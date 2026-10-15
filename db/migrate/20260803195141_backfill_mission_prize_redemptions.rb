class BackfillMissionPrizeRedemptions < ActiveRecord::Migration[8.1]
  # Copies existing inline static-prize redemptions (shop_order_id + chosen_prize_id
  # on a mission submission) into the new prize_redemptions table. The inline
  # columns stay in place until the redeem flow is fully cut over.
  def up
    safety_assured do
      execute(<<~SQL)
        INSERT INTO mission_prize_redemptions
          (user_id, mission_id, mission_prize_id, shop_order_id, source_type, source_id, created_at, updated_at)
        SELECT shop_orders.user_id, ms.mission_id, ms.chosen_prize_id, ms.shop_order_id,
               'Mission::Submission', ms.id, ms.updated_at, ms.updated_at
        FROM mission_submissions ms
        JOIN shop_orders ON shop_orders.id = ms.shop_order_id
        JOIN users ON users.id = shop_orders.user_id
        WHERE ms.shop_order_id IS NOT NULL
          AND ms.chosen_prize_id IS NOT NULL
          AND ms.deleted_at IS NULL
      SQL
    end
  end

  def down
    execute("DELETE FROM mission_prize_redemptions WHERE source_type = 'Mission::Submission'")
  end
end
