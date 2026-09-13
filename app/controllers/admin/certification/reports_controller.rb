class Admin::Certification::ReportsController < Admin::Certification::ApplicationController
    include FraudSubjectVerdict

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

      @report_groups = @reports
        .group_by(&:project_id)
        .values
        .map { |reports| reports.sort_by(&:created_at) }
        .sort_by { |reports| [ -reports.size, reports.first.created_at ] }

      project_ids = @report_groups.filter_map { |reports| reports.first.project_id }
      @pending_counts_by_project = ::Project::Report.pending.where(project_id: project_ids).group(:project_id).count
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

    def resolve_project
      authorize ::Project::Report

      project = ::Project.find(params.require(:project_id))
      resolved_count = 0

      ::Project::Report.transaction do
        project.reports.pending.lock.find_each do |report|
          report.paper_trail_event = "bulk_resolve"
          report.update!(status: :reviewed)
          resolved_count += 1
        end
      end

      redirect_to admin_certification_reports_path,
        notice: resolved_count.positive? ? "Resolved #{resolved_count} #{'report'.pluralize(resolved_count)} for #{project.title}" : "No open reports to resolve for #{project.title}"
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

        return render_fraud_subject_verdict(@report, notice_message) if fraud_subject

        redirect_to admin_certification_reports_path, notice: notice_message
      else
        redirect_to admin_certification_report_path(@report), alert: "Failed to update report"
      end
    end
end
