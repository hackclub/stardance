class CreatePollVotes < ActiveRecord::Migration[8.1]
  def change
    create_table :poll_votes do |t|
      t.references :user, index: { unique: true }, null: false, foreign_key: true
      t.string :choice, null: false

      t.timestamps
    end
  end
end
