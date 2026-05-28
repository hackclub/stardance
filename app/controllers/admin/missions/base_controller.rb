module Admin
  module Missions
    # Shared setup for the mission sub-resource controllers (steps, prizes,
    # memberships, shop_unlocks). These live under /admin/* by URL but are
    # NOT admin-only — non-admin mission owners reach them via Pundit's
    # MissionPolicy#manage?. We inherit from Admin::ApplicationController
    # to keep PaperTrail whodunnit + impersonation guards, but skip the
    # strict admin gate and replace it with the per-mission manage policy.
    class BaseController < Admin::ApplicationController
      before_action :set_mission
      before_action :authorize_mission_management

      private

      def set_mission
        slug = params[:mission_slug] || params[:slug]
        @mission = Mission.find_by!(slug: slug)
      end

      # Plain (non-namespaced) MissionPolicy so non-admin mission owners can
      # reach these admin-URL'd sub-resource controllers.
      def authorize_mission_management
        authorize @mission, :manage?, policy_class: MissionPolicy
      end
    end
  end
end
