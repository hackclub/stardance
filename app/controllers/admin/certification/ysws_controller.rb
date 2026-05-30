class Admin::Certification::YswsController < Admin::Certification::ApplicationController
  def index
    authorize ::Certification::Ysws

    @reviews = ::Certification::Ysws
      .where(reviewed_at: nil)
      .includes(:project, :user)
      .order(created_at: :asc)
  end

  def show
    @review = ::Certification::Ysws
      .includes(:project, :user, :reviewer, devlog_reviews: { post_devlog: :attachments_attachments })
      .find(params[:id])
    authorize @review

    devlog_minutes = @review.devlog_reviews.map(&:original_minutes).compact

    @stats = {
      total_minutes: devlog_minutes.sum,
      avg_minutes: devlog_minutes.any? ? (devlog_minutes.sum.to_f / devlog_minutes.count) : 0,
      max_minutes: devlog_minutes.max || 0,
      one_hour_plus_count: devlog_minutes.count { |m| m >= 60 }
    }

    @repo_info = helpers.parse_repo_info(@review.project.repo_url)
    if @repo_info
      platform = @repo_info[:platform]
      username = @repo_info[:username]
      @contribution_data = ::Certification::YswsService.fetch_contributions(platform, username)
    end
  end

  def report_fraud
    @review = ::Certification::Ysws.find(params[:id])
    authorize @review, :report_fraud?

    report = ::Project::Report.new(
      project_id: @review.project_id,
      reporter_id: current_user.id,
      reason: "YSWS project flag",
      details: params[:details],
      status: :pending
    )

    if report.save
      render json: { success: true, message: "Report submitted successfully" }, status: :created
    else
      render json: { success: false, errors: report.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def complete
    @review = ::Certification::Ysws.find(params[:id])
    authorize @review, :update?

    # Mark as reviewed (or update review timestamp if already reviewed)
    @review.update!(
      reviewed_at: Time.current,
      reviewer_id: current_user.id
    )

    # Trigger Airtable sync job
    ::Certification::Ysws::AirtableSyncJob.perform_later(@review.id)

    render json: {
      success: true,
      message: "Review completed successfully and queued for Airtable sync",
      redirect_url: admin_certification_ysws_reviews_path
    }, status: :ok
  rescue StandardError => e
    Rails.logger.error "[YswsController] Failed to complete review ##{params[:id]}: #{e.message}"
    Sentry.capture_exception(e, extra: { ysws_review_id: params[:id], user_id: current_user.id })
    render json: { success: false, error: "Failed to complete review: #{e.message}" }, status: :unprocessable_entity
  end
end
