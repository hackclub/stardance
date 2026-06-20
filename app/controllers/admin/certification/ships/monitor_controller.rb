class Admin::Certification::Ships::MonitorController < Admin::Certification::ApplicationController
  def show
    authorize :monitor, policy_class: Admin::Certification::Ships::MonitorPolicy
    @stats                   = Certification::Ship.dashboard_stats
    @chart_data              = Certification::Ship.daily_chart_data.to_json
    reviewer_data            = Certification::Ship.reviewer_daily_data
    @reviewer_chart_data     = reviewer_data.to_json
    @has_reviewer_chart_data = reviewer_data.any?
  end
end
