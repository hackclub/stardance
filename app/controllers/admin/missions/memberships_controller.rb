module Admin
  module Missions
    # One controller for both owner and reviewer membership CRUD on a
    # mission. Owner actions are admin-only (MissionPolicy#manage_owners?);
    # reviewer actions allow any mission manager (MissionPolicy#manage?,
    # already enforced by BaseController). The role is encoded in form
    # params on create and read off the membership record on destroy.
    class MembershipsController < BaseController
      before_action :set_membership, only: [ :update, :destroy ]
      before_action :authorize_owner_change_if_needed, only: [ :create, :destroy, :update ]

      def create
        user_param = membership_params[:user_id]
        user = User.find_by(id: user_param)
        user ||= User.find_by(slack_id: user_param)

        if user.nil?
          redirect_to edit_admin_mission_path(@mission.slug), alert: "User not found." and return
        end

        membership = @mission.memberships.new(user: user, role: requested_role)
        if membership.save
          redirect_to edit_admin_mission_path(@mission.slug),
                      notice: "#{requested_role.to_s.titleize} added."
        else
          redirect_to edit_admin_mission_path(@mission.slug),
                      alert: membership.errors.full_messages.to_sentence
        end
      end

      def update
        # Reserved for future use (e.g., toggling reviewer permissions).
        # Role changes between owner and reviewer aren't supported via the
        # UI today — owners are added/removed explicitly, reviewers too.
        redirect_to edit_admin_mission_path(@mission.slug),
                    alert: "Role changes aren't supported via this endpoint."
      end

      def destroy
        if @membership.owner_role?
          # Removing the last owner would orphan the mission from
          # non-admin management. Block it explicitly.
          remaining = @mission.memberships
                              .where(role: Mission::Membership.roles[:owner])
                              .where.not(id: @membership.id)
                              .count
          if remaining.zero?
            redirect_to edit_admin_mission_path(@mission.slug),
                        alert: "Can't remove the last owner — assign another owner first." and return
          end
        end

        @membership.destroy!
        redirect_to edit_admin_mission_path(@mission.slug),
                    notice: "#{@membership.role.titleize} removed."
      end

      private

      # The base controller already enforces MissionPolicy#manage? (which
      # admins + owners pass). For owner-role operations, additionally
      # enforce manage_owners? (admin-only). This is the bit non-admin
      # owners are gated out of.
      def authorize_owner_change_if_needed
        role_in_play = case action_name
        when "create"           then requested_role
        when "destroy", "update" then @membership&.role
        end
        authorize @mission, :manage_owners? if role_in_play.to_s == "owner"
      end

      # Pulled directly from raw params (not via permit) so brakeman doesn't
      # see :role in a mass-assignment list. requested_role whitelists the
      # value, and the membership is built explicitly with role: requested_role.
      def requested_role
        params.dig(:mission_membership, :role).to_s.presence_in(%w[owner reviewer])&.to_sym || :reviewer
      end

      def set_membership
        @membership = @mission.memberships.find(params[:id])
      end

      def membership_params
        params.require(:mission_membership).permit(:user_id)
      end
    end
  end
end
