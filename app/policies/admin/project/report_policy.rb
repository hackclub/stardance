module Admin
  module Project
    class ReportPolicy < ApplicationPolicy
      def index?
        user&.admin? || user&.fraud_dept?
      end

      def show?
        index?
      end

      def review?
        index?
      end

      def dismiss?
        index?
      end

      def process_demo_broken?
        index?
      end
    end
  end
end
