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

    @devlog_windows = devlog_windows_for_review(@review)
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

  def commits
    @review = ::Certification::Ysws.includes(:project).find(params[:id])
    authorize @review, :show?

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
end
