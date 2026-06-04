# frozen_string_literal: true

class CreateAmbassadorCostStats < ActiveRecord::Migration[8.1]
  def change
    create_table :ambassador_cost_stats do |t|
      t.integer :poster_cost_cents, null: false, default: 0
      t.integer :referral_cost_cents, null: false, default: 0
      t.integer :shirt_cost_cents, null: false, default: 0
      t.integer :admin_cost_cents, null: false, default: 0
      t.integer :office_grant_cost_cents, null: false, default: 0
      t.integer :total_cost_cents, null: false, default: 0
      t.integer :average_cost_per_ambassador_cents, null: false, default: 0
      t.integer :approved_ambassadors_count, null: false, default: 0
      t.jsonb :ambassador_region_breakdown, null: false, default: {}
      t.datetime :synced_at, null: false

      t.timestamps

      t.index :synced_at
    end
  end
end
