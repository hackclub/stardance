module Raffle
  class Week < ApplicationRecord
    has_paper_trail

    has_many :credited_referrals, class_name: "Raffle::Referral",
             foreign_key: :credited_week_id, dependent: :nullify, inverse_of: :credited_week
    has_many :draws, class_name: "Raffle::Draw", foreign_key: :week_id, dependent: :destroy
    has_many :weekly_claims, class_name: "Raffle::WeeklyClaim", foreign_key: :week_id, dependent: :destroy
    belongs_to :winner_participant, class_name: "Raffle::Participant", optional: true

    enum :status, { active: "active", archived: "archived" }, prefix: :status

    validates :status, presence: true
    validates :number, presence: true, uniqueness: true,
              numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 16 }

    scope :chronological, -> { order(:number) }

    def self.current
      status_active.take
    end

    # { participant_id => total_entries } for this week.
    # Base entry (1) for teens who signed up this week AND linked HCA +
    # 20 per verified referral credited to this week.
    # Teens without HCA linked get 0 entries (excluded entirely).
    def standings
      hca_linked_user_ids = ::User::Identity.where(provider: "hack_club").pluck(:user_id).to_set
      banned_user_ids = ::User.where(banned: true).pluck(:id).to_set
      eligible_participants = Raffle::Participant.where(eligible: true).index_by(&:id)

      can_enter = ->(pid) {
        p = eligible_participants[pid]
        p && !(p.user_id && banned_user_ids.include?(p.user_id)) &&
          !(p.age_group_teen? && !hca_linked_user_ids.include?(p.user_id))
      }

      base = weekly_claims.pluck(:participant_id).each_with_object({}) do |pid, h|
        h[pid] = 1 if can_enter.call(pid)
      end

      credited_referrals.status_verified.group(:participant_id).count.each do |pid, count|
        next unless can_enter.call(pid)
        base[pid] = (base[pid] || 0) + (count * 20)
      end

      base
    end

    def leaderboard(limit: 25, standings: self.standings)
      ranked = standings.sort_by { |_id, entries| -entries }
      return [] if ranked.empty?

      participants = Raffle::Participant.includes(:user).where(id: ranked.map(&:first)).index_by(&:id)
      ranked.filter_map { |id, entries| [ participants[id], entries ] if participants[id] }
            .first(limit)
    end

    def rank_for(participant, standings: self.standings)
      return nil unless participant

      mine = standings[participant.id].to_i
      return nil if mine.zero?

      standings.values.count { |entries| entries > mine } + 1
    end

    def participant_count
      standings.size
    end

    def drawn?
      winner_participant_id.present?
    end

    def voided_draws
      draws.status_voided.chronological
    end

    def voided_winner_ids
      draws.status_voided.pluck(:winner_participant_id)
    end
  end
end
