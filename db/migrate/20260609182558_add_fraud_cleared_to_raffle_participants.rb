class AddFraudClearedToRaffleParticipants < ActiveRecord::Migration[8.1]
  def change
    add_column :raffle_participants, :fraud_cleared, :boolean, default: false, null: false
  end
end
