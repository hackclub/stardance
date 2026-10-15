class My::ReportsController < ApplicationController
  before_action :authenticate_user!

  def index
    authorize :my, :show_reports?

    @body_class = "app-layout-page"

    @pagy, @reports = pagy(
      current_user.reports.includes(:project).order(created_at: :desc),
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
