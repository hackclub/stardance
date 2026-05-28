class Admin::Support::DashboardsController < Admin::ApplicationController
  def show
    authorize :support_dashboard
  end
end
