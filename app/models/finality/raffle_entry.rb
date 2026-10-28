# == Schema Information
#
# Table name: finality_raffle_entries
#
#  id            :bigint           not null, primary key
#  shipped_at    :datetime         not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  draw_id       :bigint           not null
#  ship_event_id :bigint           not null
#  user_id       :bigint           not null
#
# Indexes
#
#  index_finality_raffle_entries_on_draw_id                    (draw_id)
#  index_finality_raffle_entries_on_draw_id_and_ship_event_id  (draw_id,ship_event_id) UNIQUE
#  index_finality_raffle_entries_on_user_id                    (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (draw_id => finality_raffle_draws.id)
#  fk_rails_...  (user_id => users.id)
#
class Finality::RaffleEntry < ApplicationRecord
  self.table_name = "finality_raffle_entries"

  belongs_to :draw, class_name: "Finality::RaffleDraw", inverse_of: :entries
  belongs_to :user
  belongs_to :ship_event, class_name: "Post::ShipEvent", optional: true
  attr_readonly :draw_id, :user_id, :ship_event_id, :shipped_at
end
