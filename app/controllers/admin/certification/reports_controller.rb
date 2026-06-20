class Admin::Certification::ReportsController < Admin::Certification::ApplicationController
    before_action :set_report, only: [ :show, :review, :dismiss ]

    def index
      authorize ::Project::Report

      @time_range = params[:time_range] || "7_days"
      @limit = params[:limit] || "10"

      @reports = ::Project::Report.includes(:reporter, :project).order(created_at: :desc)
      unless params[:show_demo_broken] || params[:reason] == "demo_broken"
          @reports = @reports.where.not(reason: "demo_broken")
      end

      status_filter = params.key?(:status) ? params[:status] : "pending"
      @reports = @reports.where(status: status_filter) if status_filter.present?
      @reports = @reports.where(reason: params[:reason]) if params[:reason].present?
      @reports = @reports.where(reporter_id: params[:reporter_id]) if params[:reporter_id].present?

      @counts = {
        pending: ::Project::Report.pending.count,
        reviewed: ::Project::Report.reviewed.count,
        dismissed: ::Project::Report.dismissed.count
      }

      report_ids = @reports.map { |r| r.id.to_s }
      latest_versions = ::PaperTrail::Version
        .where(item_type: "Project::Report", item_id: report_ids)
        .where("object_changes ? 'status'")
        .order(:item_id, created_at: :desc)
        .select("DISTINCT ON (item_id) *")

      reviewer_ids = latest_versions.map(&:whodunnit).compact.uniq
      reviewers_by_id = User.where(id: reviewer_ids).index_by(&:id)

      @reviewers_by_report = latest_versions.each_with_object({}) do |version, hash|
        if version.whodunnit.present?
          hash[version.item_id.to_i] = reviewers_by_id[version.whodunnit.to_i]
        elsif version.object_changes.is_a?(Hash) && version.object_changes["auto_processed"].present?
          hash[version.item_id.to_i] = :auto
        end
      end
    end

    def show
      authorize @report
    end

    def review
      authorize @report
      update_status(:reviewed, "Report marked as reviewed")
    end

    def dismiss
      authorize @report
      update_status(:dismissed, "Report dismissed")
    end

    def process_demo_broken
      authorize ::Project::Report
      ProcessDemoBrokenReportsJob.perform_later
      redirect_to admin_certification_reports_path, notice: "Demo broken reports processing job has been queued"
    end

    private

    def set_report
      @report = ::Project::Report.find(params[:id])
    end

    def update_status(new_status, notice_message)
      old_status = @report.status

      if @report.update(status: new_status)
        ::PaperTrail::Version.create!(
          item_type: "Project::Report",
          item_id: @report.id,
          event: "update",
          whodunnit: current_user.id.to_s,
          object_changes: {
            status: [ old_status, @report.status ]
          }
        )
        redirect_to admin_certification_reports_path, notice: notice_message
      else
        redirect_to admin_certification_report_path(@report), alert: "Failed to update report"
      end
    end
end
