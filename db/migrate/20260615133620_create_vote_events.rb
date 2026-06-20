class CreateVoteEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :vote_events do |t|
      t.string :event_type, null: false
      t.datetime :occurred_at, null: false
      t.string :source, null: false, default: "server"
      t.references :user, null: false, foreign_key: true
      t.references :vote_assignment, null: true, foreign_key: true
      t.references :vote, null: true, foreign_key: true
      t.references :project, null: true, foreign_key: true
      t.references :ship_event, null: true, foreign_key: { to_table: :post_ship_events }
      t.bigint :ahoy_visit_id
      t.string :ip
      t.text :user_agent
      t.jsonb :properties, null: false, default: {}

      t.timestamps
    end

    add_index :vote_events, [ :event_type, :occurred_at ]
    add_index :vote_events, :ahoy_visit_id
    add_index :vote_events, :properties, using: :gin, opclass: :jsonb_path_ops
  end
end
