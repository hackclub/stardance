class ReportReviewsController < ApplicationController
  before_action :find_token, only: [ :review, :dismiss ]
  private

  def find_token
    @token = Report::ReviewToken.pending.find_by(token: params[:token])

    unless @token
      return redirect_to root_path, alert: "Invalid or expired review token"
    end

    unless @token.action.to_s == action_name.to_s
      redirect_to root_path, alert: "Invalid review token action"
    end
  end

end
