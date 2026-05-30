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

    # Check if review is already in unified DB
    check_unified_db_status(@review)

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

    # Run the Airtable sync synchronously so we know if it succeeds
    # Only mark as reviewed if the sync succeeds
    ActiveRecord::Base.transaction do
      # Set reviewer_id to track who completed this review
      @review.update!(reviewer_id: current_user.id)

      # Perform sync synchronously - this will raise an error if it fails
      ::Certification::Ysws::AirtableSyncJob.new.perform(@review.id)

      # Only mark as reviewed if sync succeeded
      @review.update!(reviewed_at: Time.current)
    end

    render json: {
      success: true,
      message: "Review completed and synced to Airtable successfully",
      redirect_url: admin_certification_ysws_reviews_path
    }, status: :ok
  rescue StandardError => e
    Sentry.capture_exception(e, extra: { ysws_review_id: params[:id], user_id: current_user.id })
    render json: {
      success: false,
      error: "Failed to complete review and sync to Airtable: #{e.message}. Please try again or contact support if the issue persists."
    }, status: :unprocessable_entity
  end

  private

  def check_unified_db_status(review)
    # Skip check if already marked as in unified DB
    return if review.in_unified_db?

    begin
      # Fetch record from Airtable
      table = airtable_table
      existing_record = table.all(filter: "{review_id} = '#{review.id}'").first

      # If record exists and "Automation - YSWS Record ID" is populated, mark as in unified DB
      if existing_record && existing_record["Automation - YSWS Record ID"].present?
        review.update_column(:in_unified_db, true)
      end
    rescue StandardError => e
      # Log error but don't break the page load
      Rails.logger.warn "[YswsController] Could not check unified DB status for review ##{review.id}: #{e.message}"
      Sentry.capture_exception(e, extra: { ysws_review_id: review.id })
    end
  end

  def airtable_table
    api_key = Rails.application.credentials.dig(:ysws_review, :airtable_api_key) ||
              Rails.application.credentials&.airtable&.api_key ||
              ENV["AIRTABLE_API_KEY"]
    base_id = Rails.application.credentials.dig(:ysws_review, :airtable_base_id) ||
              ENV["YSWS_REVIEW_AIRTABLE_BASE_ID"]
    table_name = Rails.application.credentials.dig(:ysws_review, :airtable_table_name) ||
                 ENV["YSWS_REVIEW_AIRTABLE_TABLE"] ||
                 "YSWS Project Submission"

    Norairrecord.table(api_key, base_id, table_name)
  end
end
