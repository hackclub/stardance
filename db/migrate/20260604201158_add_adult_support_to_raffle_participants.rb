class AddAdultSupportToRaffleParticipants < ActiveRecord::Migration[8.1]
  def change
    safety_assured do
      change_column_null :raffle_participants, :user_id, true

      add_column :raffle_participants, :github_uid, :string
      add_column :raffle_participants, :github_login, :string
      add_column :raffle_participants, :github_avatar_url, :string
      add_column :raffle_participants, :age_group, :string, null: false, default: "teen"

      remove_index :raffle_participants, :user_id
      add_index :raffle_participants, :user_id, unique: true,
                where: "user_id IS NOT NULL", name: "index_raffle_participants_on_user_id_unique"
      add_index :raffle_participants, :github_uid, unique: true,
                where: "github_uid IS NOT NULL", name: "index_raffle_participants_on_github_uid_unique"
    end
  end
end
