class Projects::ReportsController < ApplicationController
  def create
    authorize :report
    @project = ::Project.find(params[:project_id])

    return flag_via_slack if Project::Report::SLACK_ONLY_REASONS.include?(report_params[:reason])

    if current_user.reports.exists?(project: @project)
      redirect_back_or_to project_path(@project), alert: "You have already reported this project."
      return
    end

    @report = current_user.reports.build(report_params.merge(project: @project))

    if @report.save
      redirect_back_or_to project_path(@project), notice: "Report submitted. Thank you for helping us maintain quality."
    else
      redirect_back_or_to project_path(@project), alert: @report.errors.full_messages.to_sentence
    end
  end

  private

    def flag_via_slack
      result = Project::Report.flag_via_slack!(project: @project, reporter: current_user, details: report_params[:details], reason: report_params[:reason])

      case result
      when :ok
        redirect_back_or_to project_path(@project), notice: "Thanks — we've flagged this for the reviewer to take a look."
      when :details_too_short
        redirect_back_or_to project_path(@project), alert: "Share a short explanation (20+ characters)."
      when :not_allowed
        redirect_back_or_to project_path(@project), alert: "You can't report your own project."
      when :throttled
        redirect_back_or_to project_path(@project), alert: "You've already flagged this project recently."
      when :not_approved
        redirect_back_or_to project_path(@project), alert: "This project hasn't been approved, so that reason doesn't apply."
      else
        redirect_back_or_to project_path(@project), alert: "Something went wrong. Please try again."
      end
    end

    def report_params
      params.require(:project_report).permit(:reason, :details)
    end
end
