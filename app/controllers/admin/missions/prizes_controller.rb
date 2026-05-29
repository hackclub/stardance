module Admin
  module Missions
    class PrizesController < BaseController
      before_action :set_prize, only: [ :update, :destroy ]

      def create
        prize = @mission.prizes.new(prize_params.merge(position: next_position))
        if prize.save
          redirect_to edit_admin_mission_path(@mission.slug), notice: "Prize added."
        else
          redirect_to edit_admin_mission_path(@mission.slug), alert: prize.errors.full_messages.to_sentence
        end
      end

      def update
        if @prize.update(prize_params)
          redirect_to edit_admin_mission_path(@mission.slug), notice: "Prize updated."
        else
          redirect_to edit_admin_mission_path(@mission.slug), alert: @prize.errors.full_messages.to_sentence
        end
      end

      def destroy
        @prize.update!(deleted_at: Time.current)
        redirect_to edit_admin_mission_path(@mission.slug), notice: "Prize removed."
      end

      private

      def set_prize
        @prize = @mission.prizes.find(params[:id])
      end

      def prize_params
        params.require(:mission_prize).permit(:shop_item_id, :position)
      end

      def next_position
        (@mission.prizes.maximum(:position) || 0) + 1
      end
    end
  end
end
