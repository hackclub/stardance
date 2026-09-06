class Admin::Certification::YswsController < Admin::Certification::ApplicationController
  FILTER_SESSION_KEY = :admin_ysws_review_filters

  def index
    authorize ::Certification::Ysws
    if params[:reset_filters].present?
      session.delete(FILTER_SESSION_KEY)
      redirect_to admin_certification_ysws_reviews_path
      return
    end

    filters = ysws_review_filter_params? ? {} : ysws_review_filters
    if params.key?(:project_type)
      if params[:project_type].present?
        filters["project_type"] = params[:project_type]
      else
        filters.delete("project_type")
      end
    end
    # Only the opt-out is worth persisting — an absent key means the default
    # "integrity checks only" view.
    if params.key?(:with_integrity)
      if params[:with_integrity] == "0"
        filters["with_integrity"] = "0"
      else
        filters.delete("with_integrity")
      end
    end
    if params.key?(:sort)
      sort = params[:sort].presence_in(%w[length todo age])
      if sort
        filters["sort"] = sort
        filters["dir"] = params[:dir] == "asc" ? "asc" : "desc"
      else
        filters.delete("sort")
        filters.delete("dir")
      end
    end
    session[FILTER_SESSION_KEY] = filters

    @project_type   = filters["project_type"].presence
    @sort           = filters["sort"].presence_in(%w[length todo age])
    @dir            = filters["dir"] == "asc" ? "asc" : "desc"
    @with_integrity = filters["with_integrity"] != "0"

    @search = params[:search].to_s.strip

    queue = ::Certification::Ysws.pending.unclaimed_or_claimed_by(current_user)
    queue = queue.with_integrity_check if @with_integrity

    @type_counts = queue.joins(:project).group("projects.project_type").count

    scope =
      if @search.present?
        ::Certification::Ysws.search(@search)
      else
        @project_type ? queue.by_project_type(@project_type) : queue
      end

    scope = scope.with_todo_devlog_count.includes(:project, :user, :integrity_check, :claimed_by)

    default_dir = @search.present? ? :desc : :asc

    scope =
      case @sort
      when "length" then scope.order(Arel.sql("certification_ysws_reviews.original_minutes #{@dir}"))
      when "todo"   then scope.order(Arel.sql("todo_devlog_count #{@dir}")) 
      when "age"    then scope.order(Arel.sql("certification_ysws_reviews.created_at #{@dir}"))
      else               scope.order(created_at: default_dir)
      end

    @reviews = scope.to_a

    if !turbo_frame_request? &&
       Flipper.enabled?(:devlog_review_pace, current_user) &&
       !Flipper.enabled?(:reviewer_progress_panel, current_user)
      @devlog_pace  = ::Certification::Ysws.reviewer_devlog_pace(current_user.id)
      @project_pace = ::Certification::Ysws.reviewer_project_pace(current_user.id)
    end
  end

  def show
    @review = ::Certification::Ysws
      .includes(:project, :user, :reviewer, :ship_cert, :mac_analysis, devlog_reviews: { post_devlog: [ :post, :attachments_attachments ] })
      .find(params[:id])
    authorize @review

    if @review.project.nil?
      redirect_to admin_certification_ysws_reviews_path, alert: "Review ##{@review.id} has no associated project."
      return
    end

    # Claim this review for the current admin so it drops off everyone else's
    # queue. Already-decided reviews (reached via "prior reviews" history
    # links) are read-only and aren't claimed.
    @ship_cert = @review.effective_ship_cert
    @ship_cert_from_earlier_ship = @review.ship_cert_from_earlier_ship?

    if @review.pending?
      claimed = ::Certification::Ysws.atomic_claim!(@review.id, current_user)
      if claimed.nil?
        redirect_to admin_certification_ysws_reviews_path, alert: "This review is currently claimed by another admin."
        return
      end
      @review.claimed_by_id = claimed.claimed_by_id
      @review.claimed_at = claimed.claimed_at
    end

    # Check if review is already in unified DB
    @review.check_and_update_unified_db_status!

    # Earlier reviews of the same project. Their devlogs are shown frozen
    # (read-only) for context, oldest first, with only the current review's
    # devlogs editable.
    @prior_reviews = ::Certification::Ysws
      .where(project_id: @review.project_id)
      .where("id < ?", @review.id)
      .includes(devlog_reviews: { post_devlog: [ :post, :attachments_attachments ] })
      .order(:id)

    # Prior (frozen) + current devlogs, in display order, counted together in
    # the header, time stats, and chart.
    @all_devlog_reviews = @prior_reviews.flat_map(&:devlog_reviews) + @review.devlog_reviews.to_a

    devlog_minutes = @all_devlog_reviews.map(&:original_minutes).compact

    deducted_minutes = @all_devlog_reviews.sum(&:deducted_minutes)

    @stats = {
      total_minutes: devlog_minutes.sum,
      avg_minutes: devlog_minutes.any? ? (devlog_minutes.sum.to_f / devlog_minutes.count) : 0,
      max_minutes: devlog_minutes.max || 0,
      deducted_minutes: deducted_minutes,
      # Prior reviews render read-only and can't change on this page, so the
      # live recompute treats their share as a constant and only re-sums the
      # editable cards.
      frozen_deducted_minutes: deducted_minutes - @review.devlog_reviews.sum(&:deducted_minutes)
    }

    @repo_info = helpers.parse_repo_info(@review.project.repo_url)
    if @repo_info
      platform = @repo_info[:platform]
      username = @repo_info[:username]
      @contribution_data = ::Certification::YswsService.fetch_contributions(platform, username)
    end

    # The MAC pre-screen is flagged per reviewer: left nil when it's off so the
    # banner and the per-devlog notes both disappear from a single check.
    @mac_analysis = @review.mac_analysis if Flipper.enabled?(:mac_analysis, current_user)

    @lapse_timelapses = lapse_timelapses_for_ysws_review
    @lookout_recordings = lookout_recordings_for_ysws_review
    # Owner Hackatime uid for Telescreen deep-links on Lapse recordings.
    @lapse_owner_uid = @review.project.memberships.owner.first&.user&.hackatime_identity&.uid

    @devlog_windows = devlog_windows_for_review(@review)
    # Attach each recording to the devlog whose time window it was recorded in, so
    # a reviewer sees the footage that produced a devlog's logged time right beside
    # it. The top gallery still lists every recording. Lapse and Lookout bucket the
    # same way; both appear in the per-devlog section (only Lapse links to
    # Telescreen — it has no Lookout workbench).
    @devlog_lapses = ::Certification::DevlogRecordingBucketer.call(
      recordings: @lapse_timelapses,
      windows:    @devlog_windows
    )
    @devlog_lookouts = ::Certification::DevlogRecordingBucketer.call(
      recordings: @lookout_recordings,
      windows:    @devlog_windows
    )
    @devlog_commits = begin
      load_commits_with_stats(
        @devlog_windows,
        @review.project,
        github_username: @repo_info&.dig(:username),
        email:           @review.user.email
      )
    rescue => e
      Rails.logger.error("CommitGraph load failed: #{e.message}")
      {}
    end
  end

  # Whether this repo is already in the unified DB under another YSWS program.
  # Fetched from the sidebar after page load rather than during #show — the
  # Airtable round trip is far too slow to hold the review page on.
  def double_dip
    @review = ::Certification::Ysws.includes(:project).find(params[:id])
    authorize @review, :show?

    submissions = ::Certification::UnifiedYswsService.double_dip_submissions(@review.project&.repo_url)
    programs = submissions.filter_map(&:program_name).uniq

    render json: {
      double_dipped: submissions.any?,
      programs_label: programs.any? ? programs.to_sentence : "another YSWS"
    }
  end

  def commits
    @review = ::Certification::Ysws.includes(:project).find(params[:id])
    authorize @review, :show?

    return render json: { by_devlog: {}, repo_url: nil } if @review.project.nil?

    windows = devlog_windows_for_review(@review)
    commits_by_devlog = load_commits_with_stats(windows, @review.project)

    by_devlog = commits_by_devlog.transform_keys(&:to_s).transform_values do |commits|
      commits.map { |c|
        {
          sha:         c[:sha],
          short_sha:   c[:sha]&.first(7),
          message:     c[:message]&.lines&.first&.strip,
          author_name: c[:author_name],
          authored_at: c[:authored_at],
          additions:   c[:additions] || 0,
          deletions:   c[:deletions] || 0,
          url:         c[:url]
        }
      }
    end

    render json: { by_devlog: by_devlog, repo_url: @review.project.repo_url }
  end

  private

  RECORDINGS_CACHE_TTL = 1.minute

  def lapse_timelapses_for_ysws_review
    Rails.cache.fetch([ "ysws_review_recordings", "lapse", @review.project_id ], expires_in: RECORDINGS_CACHE_TTL) do
      owner = @review.project.memberships.owner.first&.user
      LapseService.timelapses_for_project(
        hackatime_user_id: owner&.hackatime_identity&.uid,
        project_keys: @review.project.hackatime_keys
      )
    end
  end

  def lookout_recordings_for_ysws_review
    Rails.cache.fetch([ "ysws_review_recordings", "lookout", @review.project_id ], expires_in: RECORDINGS_CACHE_TTL) do
      LookoutService.recordings_for_project(@review.project)
    end
  end

  def ysws_review_filters
    session[FILTER_SESSION_KEY].to_h.slice("project_type", "sort", "dir", "with_integrity")
  end

  def ysws_review_filter_params?
    params.key?(:project_type) || params.key?(:sort) || params.key?(:dir) ||
      params.key?(:with_integrity)
  end


  # Fetches all commits in the review period and buckets them by devlog ID.
  # Returns { devlog_id (integer) => [commit_hash, ...] }.
  # Adds/deletions are fetched per-commit in parallel threads (not in list response).
  def load_commits_with_stats(windows, project, github_username: nil, email: nil)
    return {} if windows.empty?

    provider = GitHost::Base.for(project.repo_url)
    return {} unless provider

    all_since  = windows.values.map { |w| Time.parse(w[:since]) }.min
    all_before = windows.values.map { |w| Time.parse(w[:before]) }.max

    all_commits = provider.fetch_commits(since: all_since, before: all_before)
    return {} if all_commits.empty?

    # Filter by author before fetching stats — list response already has author_login
    # and author_email, so we avoid stat API calls for commits we'd discard anyway.
    if github_username.present? || email.present?
      all_commits = all_commits.select do |c|
        (github_username.present? && c[:author_login]&.downcase == github_username.downcase) ||
          (email.present? && c[:author_email]&.downcase == email.downcase)
      end
    end

    return {} if all_commits.empty?

    # Fetch per-commit stats in parallel, capped at 10 concurrent connections
    # to avoid EMFILE (too many open files) on large commit histories.
    all_commits_with_stats = all_commits.each_slice(10).flat_map do |batch|
      batch.map { |c| Thread.new { provider.fetch_commit(c[:sha]) || c } }.map(&:value)
    end

    windows.transform_values do |window|
      since_t  = Time.parse(window[:since])
      before_t = Time.parse(window[:before])
      all_commits_with_stats.select { |c| c[:authored_at] && c[:authored_at] >= since_t && c[:authored_at] < before_t }
    end
  end

  # Returns { devlog_id => { since: iso8601, before: iso8601 } } for every
  # devlog post on this project, using the same window logic as the chart:
  #   first devlog  → [review_start .. devlog.created_at]
  #   middle devlog → [prev.created_at .. devlog.created_at]
  #   last devlog   → [devlog.created_at .. ship_time]
  def devlog_windows_for_review(review)
    project = review.project

    ship_post  = project.ship_event_posts.find_by(postable_id: review.post_ship_event_id)
    ship_time  = ship_post&.created_at || Time.current

    prior_ship = project.ship_event_posts
      .where("posts.created_at < ?", ship_post&.created_at || project.created_at)
      .order("posts.created_at DESC").first
    review_start = prior_ship&.created_at || Time.utc(2026, 5, 30)

    all_posts = project.posts
      .where(postable_type: "Post::Devlog")
      .joins("INNER JOIN post_devlogs ON post_devlogs.id = posts.postable_id AND post_devlogs.deleted_at IS NULL")
      .order("posts.created_at ASC")

    last_idx = all_posts.size - 1

    all_posts.each_with_index.with_object({}) do |(post, idx), windows|
      since  = idx == 0         ? review_start               : all_posts[idx - 1].created_at
      before = idx == last_idx  ? ship_time                  : post.created_at
      windows[post.postable_id] = { since: since.iso8601, before: before.iso8601 }
    end
  end

  public

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

  def unclaim
    @review = ::Certification::Ysws.includes(:project).find(params[:id])
    authorize @review, :unclaim?

    if @review.release_claim!
      Rails.logger.info "[YSWS#unclaim] user=#{current_user.id} review=#{@review.id} Released claim"
      redirect_to admin_certification_ysws_reviews_path,
                  notice: "Unclaimed review for “#{@review.project&.title || "Review ##{@review.id}"}.”"
    else
      redirect_to admin_certification_ysws_reviews_path,
                  alert: "That review can no longer be unclaimed."
    end
  end

  def complete
    Rails.logger.info "[YSWS#complete] user=#{current_user&.id} review=#{params[:id]} Starting complete action"

    @review = ::Certification::Ysws.includes(:devlog_reviews).find(params[:id])
    authorize @review, :update?

    @review.check_and_update_unified_db_status!

    if @review.in_unified_db.present?
      Rails.logger.warn "[YSWS#complete] user=#{current_user&.id} review=#{params[:id]} Blocked: already in unified DB (#{@review.in_unified_db})"
      return render json: { success: false, error: "This review is already in the unified DB" }, status: :unprocessable_entity
    end

    devlog_reviews = @review.devlog_reviews
    pending = devlog_reviews.select(&:pending?)
    if pending.any?
      Rails.logger.warn "[YSWS#complete] user=#{current_user&.id} review=#{params[:id]} Blocked: #{pending.count} unreviewed devlog(s): #{pending.map(&:id).inspect}"
      return render json: { success: false, error: "Review all devlogs before completing." }, status: :unprocessable_entity
    end

    approved = devlog_reviews.select(&:approved?)
    if approved.any? && approved.none? { |dr| dr.justification.present? }
      Rails.logger.warn "[YSWS#complete] user=#{current_user&.id} review=#{params[:id]} Blocked: no justification on any of #{approved.count} approved devlog(s)"
      return render json: { success: false, error: "Add a justification to at least one approved devlog." }, status: :unprocessable_entity
    end

    unjustified_rejections = devlog_reviews.select { |dr| dr.rejected? && dr.justification.blank? }
    if unjustified_rejections.any?
      Rails.logger.warn "[YSWS#complete] user=#{current_user&.id} review=#{params[:id]} Blocked: #{unjustified_rejections.count} rejected devlog(s) missing justification: #{unjustified_rejections.map(&:id).inspect}"
      return render json: { success: false, error: "Add a justification to every rejected devlog." }, status: :unprocessable_entity
    end

    @review.update_columns(reviewer_id: current_user.id, reviewed_at: Time.current)
    @review.touch
    Rails.logger.info "[YSWS#complete] user=#{current_user&.id} review=#{params[:id]} Marked reviewed_at=#{@review.reviewed_at}; enqueuing AirtableSyncJob"

    ::Certification::YswsAirtableSyncJob.perform_later(@review.id)
    Rails.logger.info "[YSWS#complete] user=#{current_user&.id} review=#{params[:id]} AirtableSyncJob enqueued successfully"

    render json: {
      success: true,
      message: "Review completed! Syncing to Airtable in the background...",
      redirect_url: admin_certification_ysws_reviews_path
    }, status: :ok
  rescue StandardError => e
    skip_authorization unless pundit_policy_authorized?
    Rails.logger.error "[YSWS#complete] user=#{current_user&.id} review=#{params[:id]} #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
    Sentry.capture_exception(e, tags: { category: "certification.ysws" }, extra: { ysws_review_id: params[:id], user_id: current_user&.id })
    render json: {
      success: false,
      error: "Failed to complete review: #{e.message}. Let AVD know!"
    }, status: :unprocessable_entity
  end

  def resync
    @review = ::Certification::Ysws.find(params[:id])
    authorize @review

    unless @review.reviewed_at?
      redirect_to admin_certification_ysws_review_path(@review), alert: "Cannot resync a review that hasn't been completed."
      return
    end

    ::Certification::YswsAirtableSyncJob.perform_later(@review.id)
    redirect_to admin_certification_ysws_review_path(@review), notice: "Airtable resync enqueued for review ##{@review.id}."
  end

  # Reverses a completed review: back to pending, Airtable submission record
  # deleted. Admin-only, and never for returned reviews (see YswsPolicy#undo?).
  # reset_devlogs=1 also takes every devlog verdict back to pending.
  def undo
    @review = ::Certification::Ysws.find(params[:id])
    authorize @review, :undo?

    reset_devlogs = ActiveModel::Type::Boolean.new.cast(params[:reset_devlogs]).present?
    result = ::Certification::YswsReviewUndoer.new(@review, reset_devlogs: reset_devlogs).call
    unless result.undone
      return redirect_to admin_certification_ysws_review_path(@review),
                         alert: "That review can't be undone."
    end

    # PaperTrail carries the field-level diff but no whodunnit, so this line is
    # the record of who reversed what — including the unified record id, which
    # the reversal itself throws away.
    Rails.logger.info "[YSWS#undo] user=#{current_user&.id} review=#{@review.id} " \
                      "Reset to pending; airtable_record_deleted=#{result.airtable_record_deleted} " \
                      "unified_record_id=#{result.unified_record_id} " \
                      "devlog_reviews_reset=#{result.devlog_reviews_reset}"

    # Back to the review itself, not the queue: #show re-claims it for the
    # admin who just undid it, so they can pick the review straight back up.
    notice = "Review ##{@review.id} reset to pending."
    notice += " #{result.devlog_reviews_reset} devlog verdict(s) cleared." if result.devlog_reviews_reset.positive?
    redirect_to admin_certification_ysws_review_path(@review), notice: notice
  rescue Pundit::NotAuthorizedError
    raise
  rescue StandardError => e
    Rails.logger.error "[YSWS#undo] user=#{current_user&.id} review=#{params[:id]} #{e.class}: #{e.message}"
    Sentry.capture_exception(e, tags: { category: "certification.ysws" }, extra: { ysws_review_id: params[:id], user_id: current_user&.id })
    redirect_to admin_certification_ysws_review_path(params[:id]),
                alert: "Failed to undo review: #{e.message}"
  end

  def return_to_ship_cert
    @review = ::Certification::Ysws.find(params[:id])
    authorize @review, :update?

    recert_reason = params[:recert_reason].to_s.strip.truncate(::Post::ShipEvent::RETURN_REASON_MAX_LENGTH, omission: "")
    if recert_reason.blank?
      return render json: { success: false, error: "A reason is required." }, status: :unprocessable_entity
    end

    if ::Certification::Ship.pending.exists?(project_id: @review.project_id)
      return render json: { success: false, error: "This project already has a pending ship certification." }, status: :unprocessable_entity
    end

    ActiveRecord::Base.transaction do
      approved_certs = ::Certification::Ship
        .where(project_id: @review.project_id, status: :approved)
        .lock
      approved_cert = approved_certs.find_by(id: @review.ship_cert_id) ||
                      approved_certs.find_by(post_ship_event_id: @review.post_ship_event_id) ||
                      approved_certs.order(Arel.sql("decided_at DESC NULLS LAST"), id: :desc).first

      new_cert = ::Certification::Ship.create!(
        project_id: @review.project_id,
        post_ship_event_id: @review.post_ship_event_id,
        recert_reason: recert_reason, # codeql[rb/cleartext-storage-sensitive-data]
        returned_by_id: current_user.id
      )
      @review.update!(returned_at: Time.current)

      if approved_cert&.transfer_external_certification_id_to!(new_cert)
        ::ExternalDashboard::CertReturnJob.perform_later(new_cert.id)
      elsif approved_cert
        # Nothing to hand over yet, so the return can't be sent and used to just vanish.
        # Pushing the approved cert gets a UUID back off the dashboard's duplicate
        # response, and the job chains the return itself once it lands.
        ::ExternalDashboard::ShipWebhookJob.perform_later(approved_cert.id)
      else
        Sentry.capture_message(
          "YSWS return has no approved ship cert to chain from",
          level: :error,
          tags: { category: "certification.ysws" },
          extra: { ysws_review_id: @review.id, project_id: @review.project_id, new_cert_id: new_cert.id }
        )
      end
    end

    render json: {
      success: true,
      message: "Project returned to ship certification queue.",
      redirect_url: admin_certification_ysws_reviews_path
    }, status: :ok
  rescue StandardError => e
    Sentry.capture_exception(e, tags: { category: "certification.ysws" }, extra: { ysws_review_id: params[:id], user_id: current_user&.id })
    render json: { success: false, error: "Failed to return to ship certs: #{e.message}" }, status: :unprocessable_entity
  end
end
