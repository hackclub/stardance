module Raffle
  class Draw < ApplicationRecord
    has_paper_trail

    belongs_to :week, class_name: "Raffle::Week"
    belongs_to :winner_participant, class_name: "Raffle::Participant"

    enum :status, { active: "active", voided: "voided" }, prefix: :status

    validates :status, :drawn_at, presence: true
    validates :void_reason, presence: true, if: :status_voided?

    scope :chronological, -> { order(:drawn_at) }
  end
end
