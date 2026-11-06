module Admin
  module PaperTrail
    class VersionPolicy < ApplicationPolicy
      def index?
        ViralityDecision.reviewer?(user) || user&.fraud_dept? || user&.fulfillment_person?
      end

      def show?
        if record.item_type.in?(%w[ProjectMention ViralityDecision]) || record.event == "virality_bonus_reconciled"
          return ViralityDecision.reviewer?(user)
        end

        index?
      end
    end
  end
end
