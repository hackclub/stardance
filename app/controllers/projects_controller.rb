class ProjectsController < ApplicationController
  before_action :set_project_minimal, only: [ :edit, :update, :destroy, :mark_fire, :unmark_fire ]
  before_action :set_project, only: [ :show, :readme ]

  def stats
    @project = Project.find(params[:id])
    authorize :admin, :access_admin_endpoints?

    stats = {
      devlogs_count: @project.devlogs_count,
      members_count: @project.memberships_count,
      total_hours: (@project.duration_seconds / 3600.0).round(1),
      shipped: @project.shipped?,
      created_at: @project.created_at
    }

    render json: stats
  end

  def index
    authorize Project
    @projects = current_user.projects.distinct.includes(banner_attachment: :blob)
  end

  def show
    authorize @project

    load_posts = -> {
      @project.posts
               .includes(:user, postable: [ :attachments_attachments ])
               .order(created_at: :desc)
               .select { |post| post.postable.present? }
    }

    @posts = if current_user&.can_see_deleted_devlogs?
      Post::Devlog.unscoped { load_posts.call }
    else
      load_posts.call
    end

    unless current_user && Flipper.enabled?(:"git_commit_2025-12-25", current_user)
      @posts = @posts.reject { |post| post.postable_type == "Post::GitCommit" }
    end

    unless current_user&.admin?
      @posts = @posts.reject { |post| post.postable_type == "Post::ShipEvent" && post.postable.certification_status != "approved" }
    end

    if current_user
      devlog_ids = @posts.select { |p| p.postable_type == "Post::Devlog" }.map(&:postable_id)
      @liked_devlog_ids = Like.where(user: current_user, likeable_type: "Post::Devlog", likeable_id: devlog_ids).pluck(:likeable_id).to_set
    else
      @liked_devlog_ids = Set.new
    end

    @devlog_lapse_badges = {}
    devlog_posts = @posts.select { |p| p.postable_type == "Post::Devlog" }
    if devlog_posts.any?
      timelapses = cached_lapse_timelapses
      queue_lapse_timelapses_fetch if timelapses.nil?
      @devlog_lapse_badges = build_devlog_lapse_badges(devlog_posts, timelapses)
    end

    ahoy.track "Viewed project", project_id: @project.id

    latest_ship_post = @posts.find { |post| post.postable_type == "Post::ShipEvent" }
    latest_ship_event = latest_ship_post&.postable

    @votes_for_payout = nil
    if current_user.present?
      is_owner = @project.memberships.where(role: :owner, user_id: current_user.id).exists?

      @show_ai_coding_time_ignored_card = is_owner && !current_user.has_dismissed?("ai_coding_time_ignored_card")

      if is_owner &&
          latest_ship_event.present? &&
          latest_ship_event.certification_status == "approved" &&
          latest_ship_event.payout.blank?

        required = Post::ShipEvent::VOTES_REQUIRED_FOR_PAYOUT
        current = latest_ship_event.votes.payout_countable.count
        remaining = [ required - current, 0 ].max

        @votes_for_payout = {
          current: current,
          required: required,
          remaining: remaining
        }
      end
    end
  end

  def new
    @project = Project.new
    authorize @project
    load_project_times
  end

  def create
    @project = Project.new(project_params)
    authorize @project

    validate_urls
    success = false

    Project.transaction do
      break unless @project.errors.empty? && @project.save

      @project.memberships.create!(user: current_user, role: :owner)
      link_hackatime_projects

      if @project.errors.empty?
        success = true
      else
        raise ActiveRecord::Rollback
      end
    end

    if success
      flash[:notice] = "Project created successfully"
      current_user.complete_tutorial_step! :create_project

      unless @project.tutorial?
        existing_non_tutorial_projects = current_user.projects.where(tutorial: false).where.not(id: @project.id)
        if existing_non_tutorial_projects.empty?
          FunnelTrackerService.track(
            event_name: "project_created",
            user: current_user,
            properties: { project_id: @project.id }
          )
        end
      end

      project_hours = @project.total_hackatime_hours
      if project_hours > 0
        tutorial_message [
          "Hmmm... your project has #{helpers.distance_of_time_in_words(project_hours.hours)} tracked already — nice work!",
          "You're ready to post your first devlog.",
          "Never go over 10 hours without logging progress as it might get lost!"
        ]
      else
        tutorial_message [
          "Good job — you created a project! Now cook up some code for a bit and track hours in your code editor.",
          "Once you have some time tracked, come back here and post a devlog.",
          "Remember, post devlogs every few hours. Not posting a devlog after over 10 hours of tracked time might lead to it being lost!"
        ]
      end

      redirect_to @project
    else
      flash[:alert] = "Failed to create project: #{@project.errors.full_messages.join(', ')}"
      load_project_times
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @project
    load_project_times
  end

  def update
    authorize @project

    @project.assign_attributes(project_params)
    validate_urls
    success = @project.errors.empty? && @project.save

    link_hackatime_projects if success
    # 2nd check w/ @project.errors.empty? is not redudant. this is ensures that hackatime is linked!
    if success && @project.errors.empty?
      flash[:notice] = "Project updated successfully"
      redirect_to url_from(params[:return_to]) || @project
    else
      flash.now[:alert] = "Failed to update project: #{@project.errors.full_messages.join(', ')}"
      render_update_error
    end
  end

  def destroy
    authorize @project
    force = params[:force] == "true" && policy(@project).force_destroy?

    begin
      if force && @project.shipped?
        PaperTrail::Version.create!(
          item_type: "Project",
          item_id: @project.id,
          event: "force_delete",
          whodunnit: current_user.id,
          object_changes: {
            deleted_at: [ nil, Time.current ],
            shipped_at: @project.shipped_at,
            reason: "Admin/Fraud override of ship protection",
            deleted_by: current_user.id
          }.to_yaml
        )
      end

      @project.soft_delete!(force: force)
      current_user.revoke_tutorial_step! :create_project if current_user.projects.empty?
      flash[:notice] = "Project deleted successfully"
      redirect_to projects_path
    rescue ActiveRecord::RecordInvalid => e
      flash[:alert] = e.record.errors.full_messages.to_sentence
      redirect_to @project
    end
  end

  def mark_fire
    authorize :admin, :manage_projects?

    return render(json: { message: "Project not found" }, status: :not_found) unless @project

    if @project.users.include?(current_user)
      return render(json: { message: "You cannot mark your own project as well cooked." }, status: :forbidden)
    end

    if current_user.fraud_dept? && !current_user.admin?
      if @project.users.any? { |u| u.fraud_dept? }
        return render(json: { message: "You cannot mark a fellow fraud department member's project as well cooked." }, status: :forbidden)
      end
    end

    PaperTrail.request(whodunnit: current_user.id) do
      fire_event = Post::FireEvent.create(
        body: "🔥 #{current_user.display_name} marked your project as well cooked! As a prize for your nicely cooked project, look out for a bonus prize in the mail :)"
      )

      unless fire_event.persisted?
        render json: { message: fire_event.errors.full_messages.to_sentence.presence || "Failed to mark project as 🔥" }, status: :unprocessable_entity
        next
      end

      post = @project.posts.create(user: current_user, postable: fire_event)

      if post.persisted?
        @project.mark_fire!(current_user)

        PaperTrail::Version.create!(
          item_type: "Project",
          item_id: @project.id,
          event: "mark_fire",
          whodunnit: current_user.id,
          object_changes: {
            admin_action: [ nil, "mark_fire" ],
            marked_fire_by_id: [ nil, current_user.id ],
            created_post_id: [ nil, post.id ]
          }
        )

        Project::PostToMagicJob.perform_later(@project)
        Project::MagicHappeningLetterJob.perform_later(@project)

        @project.users.each do |user|
          SendSlackDmJob.perform_later(
            user.slack_id,
            blocks_path: "notifications/projects/well_cooked",
            locals: { project: @project }
          )
        end

        render json: { message: "Project marked as 🔥!", fire: true }, status: :ok
      else
        errors = (post.errors.full_messages + fire_event.errors.full_messages).uniq
        render json: { message: errors.to_sentence.presence || "Failed to mark project as 🔥" }, status: :unprocessable_entity
      end
    end
  end

  def unmark_fire
    authorize :admin, :manage_projects?

    return render(json: { message: "Project not found" }, status: :not_found) unless @project

    PaperTrail.request(whodunnit: current_user.id) do
      @project.unmark_fire!

      PaperTrail::Version.create!(
        item_type: "Project",
        item_id: @project.id,
        event: "unmark_fire",
        whodunnit: current_user.id,
        object_changes: {
          admin_action: [ nil, "unmark_fire" ]
        }
      )

      render json: { message: "Project unmarked as 🔥", fire: false }, status: :ok
    end
  end

  def follow
    return redirect_to(project_path(params[:id]), alert: "Please sign in first.") unless current_user

    @project = Project.find(params[:id])
    authorize @project, :show?

    follow = current_user.project_follows.build(project: @project)
    if follow.save
      @project.users.each do |member|
        if member.send_notifications_for_new_followers && current_user.slack_id && member.slack_id
          SendSlackDmJob.perform_later(
            member.slack_id,
            "#{current_user.display_name} is now following your project #{@project.title}!",
            blocks_path: "notifications/new_follower",
            locals: {
              project_title: @project.title,
              project_url: project_url(@project, host: "stardance.hackclub.com", protocol: "https"),
              follower_id: current_user.slack_id
            }
          )
        end
      end
      redirect_to @project, notice: "You are now following this project."
    else
      redirect_to @project, alert: follow.errors.full_messages.to_sentence
    end
  end

  def unfollow
    return redirect_to(project_path(params[:id]), alert: "Please sign in first.") unless current_user

    @project = Project.find(params[:id])
    authorize @project, :show?

    follow = current_user.project_follows.find_by(project: @project)
    if follow&.destroy
      redirect_to @project, notice: "You have unfollowed this project."
    else
      redirect_to @project, alert: "Could not unfollow."
    end
  end

  def lapse_timelapses
    @project = Project.find(params[:id])
    authorize @project, :show?

    unless turbo_frame_request?
      redirect_to @project
      return
    end

    @is_owner = current_user.present? && @project.users.include?(current_user)

    @lapse_timelapses = cached_lapse_timelapses

    if @lapse_timelapses.nil? && should_fetch_lapse_timelapses?
      @lapse_timelapses = fetch_lapse_timelapses
      Rails.cache.write(lapse_timelapses_cache_key, @lapse_timelapses, expires_in: Cache::ProjectLapseTimelapsesJob::CACHE_TTL)
    end

    @lapse_timelapses ||= []
    @devlog_lapse_badges = build_devlog_lapse_badges(@project.devlog_posts, @lapse_timelapses)
    render layout: false
  end

  def readme
    unless turbo_frame_request?
      redirect_to @project
      return
    end

    result = ProjectReadmeFetcher.fetch(@project.readme_url)

    @readme_html =
      if result.markdown.present?
        html = MarkdownRenderer.render(result.markdown)
        ReadmeHtmlRewriter.rewrite(html: html, readme_url: @project.readme_url)
      end

    @readme_error = result.error

    render "projects/readme", layout: false
  end

  private

  # These are the same today, but they'll be different tomorrow.

  def set_project
    @project = Project.find(params[:id])
  end

  def set_project_minimal
    @project = Project.find(params[:id])
  end

  def project_params
    params.require(:project).permit(:title, :description, :demo_url, :repo_url, :readme_url, :banner, :ai_declaration)
  end

  def hackatime_project_ids
    @hackatime_project_ids ||= Array(params[:project][:hackatime_project_ids]).reject(&:blank?).map(&:to_i)
  end

  def validate_urls
    if @project.demo_url.blank? && @project.repo_url.blank? && @project.readme_url.blank?
      return
    end


    if @project.demo_url.present? && @project.repo_url.present?
      if @project.demo_url == @project.repo_url || @project.demo_url == @project.readme_url
        @project.errors.add(:base, "Demo URL and Repository URL cannot be the same")
      end
    end

    validate_url_not_dead(:demo_url, "Demo URL") if @project.demo_url.present? && @project.errors.empty?

    validate_url_not_dead(:repo_url, "Repository URL") if @project.repo_url.present? && @project.errors.empty?
    validate_url_not_dead(:readme_url, "Readme URL") if @project.readme_url.present? && @project.errors.empty?
  end

  # these links block automated requests, but we're ok with just assuming they're good
  ALLOWLISTED_DOMAINS = %w[
    npmjs.com
    crates.io
    curseforge.com
    makerworld.com
    streamlit.app
  ].freeze

  def validate_url_not_dead(attribute, name)
    require "uri"
    require "faraday"
    require "faraday/follow_redirects"

    return unless @project.send(attribute).present?

    uri = URI.parse(@project.send(attribute))

    if ALLOWLISTED_DOMAINS.any? { |domain| uri.host&.end_with?(domain) }
      return
    end

    conn = Faraday.new(
      url: uri.to_s,
      headers: { "User-Agent" => "Stardance project validator (https://stardance.hackclub.com/)" }
    ) do |faraday|
      faraday.response :follow_redirects, max_redirects: 3
      faraday.adapter Faraday.default_adapter
    end
    response = conn.get() do |req|
      req.options.timeout = 5
      req.options.open_timeout = 5
    end

    unless (200..299).cover?(response.status)
      @project.errors.add(attribute, "Your #{name} needs to return a 200 status. I got #{response.status}, is your code/website set to public!?!?")
    end


    # Copy pasted from https://github.com/hackclub/summer-of-making/blob/29e572dd6df70627d37f3718a6ebd4bafb07f4c7/app/controllers/projects_controller.rb#L275
    if attribute != :demo_url
      repo_patterns = [
        %r{/blob/}, %r{/tree/}, %r{/src/}, %r{/raw/}, %r{/commits/},
        %r{/pull/}, %r{/issues/}, %r{/compare/}, %r{/releases/},
        /\.git$/, %r{/commit/}, %r{/branch/}, %r{/blame/},

        %r{/projects/}, %r{/repositories/}, %r{/gitea/}, %r{/cgit/},
        %r{/gitweb/}, %r{/gogs/}, %r{/git/}, %r{/scm/},

        /\.(md|py|js|ts|jsx|tsx|html|css|scss|php|rb|go|rs|java|cpp|c|h|cs|swift)$/
      ]

      # Known code hosting platforms (not required, but used for heuristic)
      known_platforms = [
        "github", "gitlab", "bitbucket", "dev.azure", "sourceforge",
        "codeberg", "sr.ht", "replit", "vercel", "netlify", "glitch",
        "hackclub", "gitea", "git", "repo", "code"
      ]

      path = uri.path.downcase
      host = uri.host.downcase

      is_valid_repo_url = false

      if repo_patterns.any? { |pattern| path.match?(pattern) }
        is_valid_repo_url = true
      elsif attribute == :readme_url && (host.include?("raw.githubusercontent") || path.include?("/readme") || path.end_with?(".md") || path.end_with?("readme.txt"))
        is_valid_repo_url = true
      elsif known_platforms.any? { |platform| host.include?(platform) }
        is_valid_repo_url = path.split("/").size > 2
      elsif path.split("/").size > 1 && path.exclude?("wp-") && path.exclude?("blog")
        is_valid_repo_url = true
      end

      unless is_valid_repo_url
        @project.errors.add(attribute, "#{name} does not appear to be a valid repository or project URL")
      end
    end

  rescue URI::InvalidURIError
    @project.errors.add(attribute, "#{name} is not a valid URL")
  rescue Faraday::ConnectionFailed => e
    @project.errors.add(attribute, "Please make sure the URL is valid and reachable: #{e.message}")
  rescue StandardError => e
    @project.errors.add(attribute, "#{name} could not be verified (idk why, pls let a admin know if this is happening a lot and your sure that the URL is valid): #{e.message}")
  end

  def link_hackatime_projects
    # Unlink hackatime projects that were removed
    @project.hackatime_projects.where.not(id: hackatime_project_ids).find_each do |hp|
      hp.update(project: nil)
    end

    return if hackatime_project_ids.empty?

    current_user.hackatime_projects.where(id: hackatime_project_ids).find_each do |hp|
      unless hp.update(project: @project)
        hp.errors.full_messages.each do |message|
          @project.errors.add(:base, "Hackatime project #{hp.name}: #{message}")
        end
      end
    end
  end

  def load_project_times
    result = current_user.try_sync_hackatime_data!
    @project_times = result&.dig(:projects) || {}
  end

  def fetch_lapse_timelapses
    ProjectLapseTimelapsesFetcher.new(@project).call
  end

  def cached_lapse_timelapses
    Rails.cache.read(lapse_timelapses_cache_key)
  end

  def queue_lapse_timelapses_fetch
    return unless should_fetch_lapse_timelapses?
    return if Rails.cache.exist?(lapse_timelapses_cache_key)

    Cache::ProjectLapseTimelapsesJob.perform_later(@project.id)
  end

  def should_fetch_lapse_timelapses?
    return false unless ENV["LAPSE_API_BASE"].present?
    return false unless @project.hackatime_keys.present?

    hackatime_identity = @project.memberships.owner.first&.user&.hackatime_identity
    hackatime_identity&.uid.present?
  end

  def lapse_timelapses_cache_key
    Cache::ProjectLapseTimelapsesJob.cache_key(@project.id)
  end

  def build_devlog_lapse_badges(devlog_posts, timelapses)
    return {} if devlog_posts.blank? || timelapses.blank?

    timelapse_times = timelapses.filter_map do |timelapse|
      created_at_ms = timelapse["createdAt"]
      next if created_at_ms.blank?

      Time.at(created_at_ms.to_i / 1000.0)
    rescue ArgumentError, TypeError
      nil
    end.sort

    return {} if timelapse_times.blank?

    badges = {}
    previous_time = @project.created_at
    devlog_posts.sort_by(&:created_at).each do |devlog_post|
      current_time = devlog_post.created_at
      badges[devlog_post.postable_id] = timelapse_times.any? { |time| time > previous_time && time <= current_time }
      previous_time = current_time
    end

    badges
  end

  def render_update_error
    if url_from(params[:return_to])&.include?("ships")
      @last_ship = @project.last_ship_event
      @devlogs_for_ship = @project.devlog_posts.includes(:user, postable: [ { attachments_attachments: :blob } ])
      @devlogs_for_ship = @devlogs_for_ship.where("posts.created_at > ?", @last_ship.created_at) if @last_ship
      @step = 2
      render "projects/ships/new", status: :unprocessable_entity
    else
      render :edit, status: :unprocessable_entity
    end
  end
end
