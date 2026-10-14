class MissionSubmissionsController < ApplicationController
  before_action :set_body_class
  before_action :set_submission

  def redeem
    authorize @submission
    @prizes = @submission.unredeemed_prizes.to_a
    @claimed_prizes = @submission.redeemable_prizes
      .where(id: @submission.prize_redemptions.select(:mission_prize_id))

    # Nothing left to choose between, so skip the picker.
    redirect_to shop_item_path(@prizes.first.shop_item, mission_submission_id: @submission.id) if @prizes.one?
  end

  private

  def set_body_class
    @body_class = "app-layout-page"
  end

  def set_submission
    @submission = Mission::Submission.find(params[:id])
  end
end
