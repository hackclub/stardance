class Admin::Fraud::DashboardsController < Admin::ApplicationController
  def show
    authorize :fraud_dashboard
  end
end
