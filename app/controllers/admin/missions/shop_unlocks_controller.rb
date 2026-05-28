module Admin
  module Missions
    class ShopUnlocksController < BaseController
      def create
        unlock = @mission.shop_unlocks.new(shop_item_id: params.dig(:mission_shop_unlock, :shop_item_id))
        if unlock.save
          redirect_to edit_admin_mission_path(@mission.slug), notice: "Shop unlock added."
        else
          redirect_to edit_admin_mission_path(@mission.slug), alert: unlock.errors.full_messages.to_sentence
        end
      end

      def destroy
        unlock = @mission.shop_unlocks.find(params[:id])
        unlock.destroy!
        redirect_to edit_admin_mission_path(@mission.slug), notice: "Shop unlock removed."
      end
    end
  end
end
