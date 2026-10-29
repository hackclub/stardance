module Admin
  module Missions
    # Lets a mission admin unlock this mission's shop items for one user
    # without an approved submission. Admin-only (manage_owners?): a grant
    # skips review, so non-admin mission owners can't hand them out.
    class ShopUnlockGrantsController < BaseController
      include UserLookup

      before_action { authorize @mission, :manage_owners? }

      def create
        query = params.dig(:mission_shop_unlock_grant, :user_id).to_s.strip
        user = find_user(query)
        return back_to_edit(alert: "No user found for \"#{query}\". Use their email, username, user ID or Slack ID.") if user.nil?

        grant = @mission.shop_unlock_grants.new(
          user: user,
          granted_by: current_user,
          reason: params.dig(:mission_shop_unlock_grant, :reason).to_s.strip.presence
        )
        if grant.save
          back_to_edit notice: "#{user.display_name} can now buy this mission's shop items."
        elsif grant.errors.of_kind?(:user_id, :taken)
          back_to_edit alert: "#{user.display_name} already has this mission's shop unlocks."
        else
          back_to_edit alert: grant.errors.full_messages.to_sentence
        end
      end

      def destroy
        grant = @mission.shop_unlock_grants.find(params[:id])
        grant.destroy!
        back_to_edit notice: "Shop unlock grant removed."
      end

      private

      # The section is a Turbo Frame, so the page-level flash never reaches it.
      def back_to_edit(notice: nil, alert: nil)
        redirect_to edit_admin_mission_path(@mission.slug),
                    flash: { shop_unlock_grants_notice: notice, shop_unlock_grants_alert: alert }.compact
      end
    end
  end
end
