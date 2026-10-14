class Home::DiscoverRailsController < ApplicationController
  skip_before_action :remember_page

  def streak
    authorize :home, :index?
    current_user&.sync_streak_now! if params[:refresh].present?
    render layout: false
  end

  def certificate
    authorize :home, :index?
    render layout: false
  end
end
