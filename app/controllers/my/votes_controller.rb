class My::VotesController < ApplicationController
  before_action :authenticate_user!

  def index
    authorize :my, :show_ratings?

    @body_class = "app-layout-page"

    @pagy, @votes = pagy(
      current_user.votes.includes(:project).order(created_at: :desc),
      limit: 25
    )
  end

  private

  def authenticate_user!
    return if current_user.present?

    store_return_to
    redirect_to root_path, alert: "Please sign in to continue."
  end
end
