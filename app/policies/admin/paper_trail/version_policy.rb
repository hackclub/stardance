module Admin
  module PaperTrail
    class VersionPolicy < ApplicationPolicy
      def index?
        user&.admin? || user&.fraud_dept? || user&.fulfillment_person?
      end

      def show?
        index?
      end
    end
  end
end
