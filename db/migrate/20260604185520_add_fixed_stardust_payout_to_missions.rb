class AddFixedStardustPayoutToMissions < ActiveRecord::Migration[8.1]
  def change
    add_column :missions, :fixed_stardust_payout, :integer
  end
end
