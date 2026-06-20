module Raffle
  class WeeklyClaim < ApplicationRecord
    belongs_to :participant, class_name: "Raffle::Participant"
    belongs_to :week, class_name: "Raffle::Week"

    validates :participant_id, uniqueness: { scope: :week_id }
  end
end
