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
        query = membership_params[:user_id].to_s.strip
        user = find_user(query)

        if user.nil?
          back_to_edit requested_role, alert: "No user found for \"#{query}\". Use their email, username, user ID or Slack ID." and return
        end

        membership = @mission.memberships.new(user: user, role: requested_role)
        if membership.save
          back_to_edit requested_role, notice: "#{user.display_name} added as #{requested_role}."
        elsif membership.errors.of_kind?(:user_id, :taken)
          back_to_edit requested_role, alert: "#{user.display_name} is already #{requested_role == :owner ? 'an owner' : 'a reviewer'}."
        else
          back_to_edit requested_role, alert: membership.errors.full_messages.to_sentence
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
        back_to_edit @membership.role, notice: "#{@membership.role.titleize} removed."
      end

      private

      # Accepts an email, a username (with or without "@", or a profile URL),
      # a numeric user ID, or a Slack ID.
      def find_user(query)
        return if query.blank? || query.length > 320
        return User.find_by("LOWER(email) = ?", query.downcase) if email_like?(query)

        handle = query.sub(%r{\Ahttps?://[^/]+/}, "").delete_prefix("@")
        (User.find_by(id: query) if query.match?(/\A\d+\z/)) ||
          User.find_by(slack_id: query) ||
          User.find_by("LOWER(display_name) = ?", handle.downcase)
      end

      # Plain string checks rather than a regex: an email has one "@" that
      # isn't leading (that's "@username") and no "/" (that's a profile URL).
      # The database lookup is what decides whether it really matches.
      def email_like?(query)
        query.count("@") == 1 && !query.start_with?("@") && !query.include?("/")
      end

      # The reviewers section is a Turbo Frame, so the page-level flash never
      # reaches it; reviewer messages use their own keys that the frame
      # renders. Owner forms submit full-page and keep the normal flash.
      def back_to_edit(role, notice: nil, alert: nil)
        flash = if role.to_s == "reviewer"
          { reviewers_notice: notice, reviewers_alert: alert }.compact
        else
          { notice:, alert: }.compact
        end
        redirect_to edit_admin_mission_path(@mission.slug), flash:
      end

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
