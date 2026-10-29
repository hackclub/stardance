# == Schema Information
#
# Table name: finality_raffle_selections
#
#  id               :bigint           not null, primary key
#  entry_count      :integer          not null
#  pool_entry_count :integer          not null
#  prize_key        :string           not null
#  slot             :integer          not null
#  void_reason      :text
#  voided_at        :datetime
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  draw_id          :bigint           not null
#  selected_by_id   :bigint           not null
#  user_id          :bigint           not null
#  voided_by_id     :bigint
#
# Indexes
#
#  finality_raffle_one_active_selection_per_slot       (draw_id,prize_key,slot) UNIQUE WHERE (voided_at IS NULL)
#  finality_raffle_one_prize_per_person                (draw_id,user_id) UNIQUE WHERE (voided_at IS NULL)
#  index_finality_raffle_selections_on_draw_id         (draw_id)
#  index_finality_raffle_selections_on_selected_by_id  (selected_by_id)
#  index_finality_raffle_selections_on_user_id         (user_id)
#  index_finality_raffle_selections_on_voided_by_id    (voided_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (draw_id => finality_raffle_draws.id)
#  fk_rails_...  (selected_by_id => users.id)
#  fk_rails_...  (user_id => users.id)
#  fk_rails_...  (voided_by_id => users.id)
#
class Finality::RaffleSelection < ApplicationRecord
  self.table_name = "finality_raffle_selections"

  has_paper_trail
  belongs_to :draw, class_name: "Finality::RaffleDraw", inverse_of: :selections
  belongs_to :user
  belongs_to :selected_by, class_name: "User"
  belongs_to :voided_by, class_name: "User", optional: true

  attr_readonly :draw_id, :user_id, :prize_key, :slot, :entry_count, :pool_entry_count, :selected_by_id
  validates :prize_key, inclusion: { in: Finality::RAFFLE_PRIZES.pluck(:key) }
  validates :slot, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: ->(selection) { selection.prize&.fetch(:quantity, 0) || 0 } }
  validates :entry_count, numericality: { only_integer: true, greater_than: 0 }
  validates :pool_entry_count, numericality: { only_integer: true, greater_than_or_equal_to: :entry_count }
  validates :void_reason, presence: true, length: { maximum: 1_000 }, if: :voided_at?
  validates :voided_by, presence: true, if: :voided_at?

  scope :active, -> { where(voided_at: nil) }

  def prize = Finality.raffle_prize(prize_key)
  def label = "#{prize[:name]}#{' VIP' if prize_key == 'vip'} ##{slot}"
end
