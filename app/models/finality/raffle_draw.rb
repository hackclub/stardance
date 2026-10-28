# == Schema Information
#
# Table name: finality_raffle_draws
#
#  id                :bigint           not null, primary key
#  entry_count       :integer          default(0), not null
#  frozen_at         :datetime
#  key               :string           not null
#  participant_count :integer          default(0), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  frozen_by_id      :bigint
#
# Indexes
#
#  index_finality_raffle_draws_on_frozen_by_id  (frozen_by_id)
#  index_finality_raffle_draws_on_key           (key) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (frozen_by_id => users.id)
#
class Finality::RaffleDraw < ApplicationRecord
  self.table_name = "finality_raffle_draws"

  KEY = "finality_2026".freeze
  class Error < StandardError; end

  has_paper_trail
  belongs_to :frozen_by, class_name: "User", optional: true
  has_many :entries, class_name: "Finality::RaffleEntry", foreign_key: :draw_id, inverse_of: :draw, dependent: :restrict_with_exception
  has_many :selections, class_name: "Finality::RaffleSelection", foreign_key: :draw_id, inverse_of: :draw, dependent: :restrict_with_exception

  validates :key, inclusion: { in: [ KEY ] }
  attr_readonly :key

  def self.current = find_by(key: KEY)

  # No drawing, notifications, or awards: this only fixes the entry pool.
  def self.freeze_pool!(actor:)
    raise Error, "Only admins can prepare the raffle." unless actor&.admin?

    PaperTrail.request(whodunnit: actor.id) do
      transaction do
        draw = create_or_find_by!(key: KEY)
        draw.with_lock do
          unless draw.frozen_at?
            raise Error, "Wait until raffle submissions close before freezing entries." if Time.current < Finality.window.end
            raise Error, "Resolve the remaining ship reviews before freezing entries." if Finality.pending_raffle_ships.exists?

            ships = Finality.approved_raffle_ships.order(:id).pluck(:id, "posts.user_id", "posts.created_at")
            raise Error, "There are no approved entries to draw from." if ships.empty?

            now = Time.current
            draw.entries.insert_all!(ships.map do |ship_id, user_id, shipped_at|
              { user_id: user_id, ship_event_id: ship_id, shipped_at: shipped_at, created_at: now, updated_at: now }
            end)
            draw.paper_trail_event = "freeze_raffle_pool"
            draw.update!(frozen_at: now, frozen_by: actor, entry_count: ships.size, participant_count: ships.map(&:second).uniq.size)
          end
        end
        draw
      end
    end
  end

  # Recheck bans and rejected/deleted ships without admitting new entries into
  # the frozen pool. Every previous selection (including rerolls) is excluded.
  def available_entry_counts
    entries.joins(:user, ship_event: :post)
           .where(users: { banned: false }, post_ship_events: { certification_status: "approved" })
           .where(posts: { created_at: Finality.window })
           .where("posts.user_id = finality_raffle_entries.user_id")
           .where.not(user_id: selections.select(:user_id))
           .group(:user_id).order(:user_id).count
  end

  def roll!(prize_key:, actor:)
    prize = Finality.raffle_prize(prize_key)
    raise Error, "Choose a valid prize." unless prize

    audited_lock(actor) do
      filled_slots = selections.active.where(prize_key: prize_key).pluck(:slot)
      remaining_slots = (1..prize[:quantity]).to_a - filled_slots
      pool = available_entry_counts
      remaining_slots.count do |slot|
        if pool.any?
          selected = select_winner!(pool, prize_key: prize_key, slot: slot, actor: actor)
          pool.delete(selected.user_id)
          true
        else
          false
        end
      end
    end
  end

  def reroll!(selection_id:, reason:, actor:)
    reason = reason.to_s.strip
    raise Error, "Give a reason for this reroll (up to 1,000 characters)." if reason.blank? || reason.length > 1_000

    audited_lock(actor) do
      previous = selections.find(selection_id)
      raise Error, "That result was already rerolled. Refresh to see its replacement." if previous.voided_at?

      pool = available_entry_counts
      raise Error, "No eligible replacements remain. The current result has been kept." if pool.empty?

      previous.paper_trail_event = "reroll_raffle_selection"
      previous.update!(voided_at: Time.current, voided_by: actor, void_reason: reason)
      select_winner!(pool, prize_key: previous.prize_key, slot: previous.slot, actor: actor)
    end
  end

  private

  def audited_lock(actor)
    raise Error, "Only admins can draw or reroll." unless actor&.admin?

    PaperTrail.request(whodunnit: actor.id) do
      with_lock do
        raise Error, "Freeze the approved entry pool first." unless frozen_at?
        yield
      end
    end
  end

  def select_winner!(pool, prize_key:, slot:, actor:)
    total = pool.values.sum
    ticket = SecureRandom.random_number(total)
    user_id, weight = pool.find do |_id, entries|
      ticket -= entries
      ticket.negative?
    end

    selection = selections.build(user_id: user_id, prize_key: prize_key, slot: slot,
                                 entry_count: weight, pool_entry_count: total, selected_by: actor)
    selection.paper_trail_event = "draw_raffle_selection"
    selection.save!
    selection
  end
end
