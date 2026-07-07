class Admin::Fraud::DashboardsController < Admin::ApplicationController
  def show
    authorize :fraud_dashboard
    @pending_orders_count = ShopOrder.where(aasm_state: %w[pending awaiting_verification awaiting_verification_call awaiting_periodical_fulfillment on_hold]).count
    @pending_fraud_reports_count = ::Project::Report.pending.where(reason: "fraud").count

    @order_stats = ShopOrder.dashboard_stats
  end
end
