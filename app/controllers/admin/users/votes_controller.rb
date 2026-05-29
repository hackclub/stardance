class Admin::Users::VotesController < Admin::ApplicationController
  def index
    @user = User.find(params[:user_id])
    authorize @user, :view_votes?

    @pagy, @votes = pagy(
      @user.votes.includes(:project).order(created_at: :desc)
    )
  end
end
