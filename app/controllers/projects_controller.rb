class ProjectsController < ApplicationController
  include TimelinePostPreloading

  # Mission + payout-votes render as discover-rail modules on the project page.
  # The expanded mission module also previews the next guide step.
  discover_rail_widgets :project_mission_expanded, :mission_browse, :ship_intro, :payout_votes, :upcoming_events,
                        context: -> { { project: @project, votes_for_payout: @votes_for_payout } }

  before_action :set_project_minimal, only: [ :edit, :update, :destroy ]
  before_action :set_project, only: [ :show, :readme, :add_test_time ]
  before_action :redirect_guest_owner_to_link!, only: [ :show, :readme, :edit, :update ]

  def show
    authorize @project

    @body_class = "app-layout-page"
    if params[:welcome] == "1"
      welcomed_ids = Array(session[:project_welcomed_ids])
      @body_class += " project-welcoming" unless welcomed_ids.include?(@project.id)
      session[:project_welcomed_ids] = (welcomed_ids + [ @project.id ]).last(20)

      # Strip wizard pages from the back-stack so the project page's back
      # button skips the (one-time) setup flow.
      if session[:previous_pages].is_a?(Array)
        session[:previous_pages] = session[:previous_pages].reject { |p| p.to_s.include?("/projects/setup") }
      end
    end

    prepare_project_show_context

    if params[:embed].present?
      @hide_sidebar = true
      render layout: "embed"
    end
  end

  def prepare_project_show_context
    @members = @project.users.where(banned: false).to_a
    @is_member = current_user && @members.include?(current_user)
    @active_nav_slug = @is_member ? "projects" : "home"
    @can_edit_project = policy(@project).update?
    @is_owner = current_user && @project.memberships.exists?(user_id: current_user.id, role: :owner)
    @admin_editing_project = !@is_member && current_user&.admin?
    @follower_count = @project.project_follows.size
    @viewer_follow = current_user && @project.project_follows.find_by(user_id: current_user.id)
    @total_hours = (@project.duration_seconds / 3600.0).round
    @test_time_granted = session[test_time_session_key].present?
    @hackatime_times = {}
    @project_has_devlogs = @project.posts.where(postable_type: "Post::Devlog").exists?

    if @is_member && current_user
      @composer_devlog = Post::Devlog.new
      @composer_projects = current_user.projects.order(updated_at: :desc)

      @hackatime_linked = current_user.hackatime_identity.present?

      if @hackatime_linked
        @linked_hackatime_projects = @project.hackatime_projects.where(user: current_user)
        @all_hackatime_projects = current_user.hackatime_projects
        result = current_user.try_sync_hackatime_data!
        @hackatime_times = result&.dig(:projects) || {}
        @hackatime_token_stale = current_user.hackatime_token_stale?
        identity = current_user.hackatime_identity
        @unposted_seconds = @project.unlogged_hackatime_seconds(
          identity.uid,
          user: current_user,
          access_token: identity.access_token
        ).to_i

        linked_ids = @linked_hackatime_projects.map(&:id).to_set
        taken_project_ids = @all_hackatime_projects.map(&:project_id).compact.uniq - [ @project.id ]
        taken_titles = Project.where(id: taken_project_ids).pluck(:id, :title).to_h
        @hackatime_dropdown_items = @all_hackatime_projects.map do |hp|
          seconds = @hackatime_times[hp.name] || 0
          taken = hp.project_id.present? && hp.project_id != @project.id
          {
            id: hp.id,
            name: hp.name,
            seconds: seconds,
            hours: (seconds / 3600.0).round(1),
            taken: taken,
            taken_by: taken ? taken_titles[hp.project_id] : nil,
            linked: linked_ids.include?(hp.id)
          }
        end
      end
    end


    load_posts = ->(include_deleted_devlogs: false) {
      scope = @project.posts
                       .visible_to(current_user)
                       .preload(:postable)
                       .order(created_at: :desc)
      unless include_deleted_devlogs
        scope = scope.joins("LEFT JOIN post_devlogs ON posts.postable_type = 'Post::Devlog' AND posts.postable_id = post_devlogs.id")
                     .where("posts.postable_type != 'Post::Devlog' OR post_devlogs.deleted_at IS NULL")
      end

      build_posts = -> {
        posts = scope.select { |post| post.postable.present? }
        preload_timeline_postables(posts, project_context: true)
        posts
      }

      # Post::Devlog has its own default_scope (SoftDeletable), which the
      # preloader above respects regardless of the SQL filter toggled just
      # above — without unscoping, a deleted devlog's postable silently
      # comes back nil and gets dropped, even when the viewer is authorized
      # to see it.
      include_deleted_devlogs ? Post::Devlog.unscoped(&build_posts) : build_posts.call
    }

    @posts = if policy(@project).view_deleted_devlogs?
      load_posts.call(include_deleted_devlogs: true)
    else
      load_posts.call
    end

    unless current_user && Flipper.enabled?(:"git_commit_2025-12-25", current_user)
      @posts = @posts.reject { |post| post.postable_type == "Post::GitCommit" }
    end

    # A misfiled ship is withdrawn, so it comes off the timeline for everyone,
    # its owner included: the queue-mismatch card explains what happened and
    # asks the question, and leaving the ship card up alongside it just reads as
    # a live ship. Disputing the flag puts the ship back to pending and it
    # returns here.
    @posts = @posts.reject do |post|
      post.postable_type == "Post::ShipEvent" &&
        post.postable.certification_status.in?(Post::ShipEvent::HIDDEN_STATUSES)
    end

    @queue_mismatch_review = visible_queue_mismatch

    # Shipwright verdicts are rendered straight from the review records —
    # they're private to project members, so they never become Post rows.
    @timeline_entries = Project.sort_timeline_entries(
      @posts + visible_ship_decisions + visible_funding_requests
    )

    @show_project_onboarding = @is_member && @timeline_entries.empty?
    @project_onboarding_mission = @project.current_mission

    @available_missions = if @is_member && @project.current_mission.nil? && !@project.shipped?
      taken_mission_ids = current_user.projects
                                      .where(deleted_at: nil)
                                      .joins(:mission_attachments)
                                      .where(project_mission_attachments: { detached_at: nil, deleted_at: nil })
                                      .pluck("project_mission_attachments.mission_id")
                                      .uniq
      Mission.available
             .where.not(id: taken_mission_ids)
             .includes(:icon_attachment, :prerequisites)
             .order(featured_at: :desc)
             .to_a
             .select { |m| m.prerequisites_met_by?(current_user) }
             .first(12)
    else
      []
    end

    if current_user
      devlog_ids = @posts.select { |p| p.postable_type == "Post::Devlog" }.map(&:postable_id)
      @liked_devlog_ids = Like.where(user: current_user, likeable_type: "Post::Devlog", likeable_id: devlog_ids).pluck(:likeable_id).to_set
    else
      @liked_devlog_ids = Set.new
    end

    track_event "Viewed project", project_id: @project.id
    if current_user.present? && !@is_member
      @project.send_gorse_feedback_later(user: current_user, item: @project, feedback_type: :read, comment: "project_show")
    end

    @latest_ship_post = @posts.find { |post| post.postable_type == "Post::ShipEvent" }
    latest_ship_event = @project.ship_events.where(certification_status: "approved").first

    @rejected_mission_sub = @posts
      .select { |p| p.postable_type == "Post::ShipEvent" }
      .lazy.map { |p| p.postable&.mission_submission }
      .find { |sub| sub&.rejected? }

    @votes_for_payout = nil
    if current_user.present?
      can_review_payout = @is_member || current_user.admin?

      if Post::ShipEvent.payout_feature_enabled?(current_user) &&
          can_review_payout &&
          latest_ship_event.present? &&
          latest_ship_event.certification_status == "approved" &&
          !latest_ship_event.mission_submission&.rejected?

        is_static = latest_ship_event.mission_submission&.payout_path == "static_prize"

        required = Post::ShipEvent::VOTES_REQUIRED_FOR_PAYOUT
        current = latest_ship_event.votes.payout_countable.count
        remaining = [ required - current, 0 ].max

        ratings_remaining = [ -latest_ship_event.payout_recipient.vote_balance, 0 ].max

        @votes_for_payout = {
          ship_event: latest_ship_event,
          current: current,
          required: required,
          remaining: remaining,
          ratings_remaining: ratings_remaining,
          static_prize: is_static,
          # Suppresses the payout checklist entirely; see PayoutVotesWidget.
          hardware: @project.hardware?,
          paid_out: latest_ship_event.payout.present?,
          estimated_payout: latest_ship_event.estimated_payout,
          review_open: latest_ship_event.payout_review_open?,
          review_deadline: latest_ship_event.payout_review_deadline,
          reason_votes: latest_ship_event.payout_basis_locked_at? ? latest_ship_event.payout_counted_votes : [],
          admin_view: current_user.admin? && !@is_member
        }
      end
    end
  end
  private :prepare_project_show_context

  # Who can see a project's hardware review history (funding requests + ship
  # verdicts) on its page:
  #   - reviewers always can - they need the history to do their job;
  #   - the project's own members and admins can while the surface's rollout flag
  #     is on for them (the amount asked for and the reviewer's feedback are
  #     otherwise the team's business);
  #   - and when the +public_hardware_reviews+ flag is on, anyone viewing the
  #     project can - logged in or not.
  def hardware_review_history_visible?(rollout_flag)
    return true if Flipper.enabled?(:public_hardware_reviews)
    return false unless current_user
    return true if current_user.can_review?
    return false unless Flipper.enabled?(rollout_flag, current_user)

    @is_member || current_user.admin?
  end
  private :hardware_review_history_visible?

  # Decided Shipwright reviews. Same audience as the funding history below.
  def visible_ship_decisions
    return [] unless hardware_review_history_visible?(:week_1_release)

    @project.ship_reviews
            .decided
            .includes(:reviewer)
            .with_attached_verdict_video
            .to_a
  end
  private :visible_ship_decisions

  # Funding requests interleaved into the feed (see
  # Project#timeline_funding_requests), so a returned review keeps its place as
  # newer devlogs are posted rather than only the latest request showing.
  def visible_funding_requests
    return [] unless hardware_review_history_visible?(:hardware_flow)

    @project.timeline_funding_requests.includes(:reviewer).to_a
  end
  private :visible_funding_requests

  # The "your submission is in the wrong queue" question, if one is open. Same
  # audience as the funding requests above: members and admins only.
  def visible_queue_mismatch
    return nil unless current_user
    return nil unless @is_member || current_user.admin?
    return nil unless Flipper.enabled?(:hardware_flow, current_user)

    @project.review_awaiting_queue_answer
  end
  private :visible_queue_mismatch

  def add_test_time
    authorize @project

    unless Flipper.enabled?(:test_time, current_user)
      redirect_back fallback_location: project_path(@project), alert: "Test time is not available"
      return
    end

    # NB: query the table directly rather than current_user.hackatime_projects —
    # that reader is overridden (User::HackatimeSync) to only surface real synced
    # projects, so it would never find the test-time row and a second click would
    # try to insert a duplicate, tripping the (user_id, name) uniqueness check.
    hackatime_project = User::HackatimeProject.find_or_initialize_by(user: current_user, name: test_time_hackatime_project_name)
    hackatime_project.project = @project
    hackatime_project.save!

    session[test_time_session_key] = true
    redirect_back fallback_location: project_path(@project),
                  notice: "15 minutes of test time added - post your devlog now"
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: project_path(@project),
                  alert: e.record.errors.full_messages.to_sentence
  end

  def new
    # First-timers get bounced to the setup wizard.
    if current_user&.projects&.none?
      # /projects/new just bounces to setup for first-timers — pop it from the
      # back-stack so the idea step's back button skips over it.
      if session[:previous_pages].is_a?(Array)
        session[:previous_pages].delete_if { |p| p.to_s.include?("/projects/new") }
      end
      redirect_to projects_setup_path and return
    end

    @project = Project.new
    authorize @project
    @missions = Mission.available
                       .where.not(id: missions_user_already_has_a_project_on)
                       .includes(:icon_attachment, :banner_attachment, :prerequisites)
                       .order(featured_at: :desc)
                       .to_a
                       .select { |m| m.prerequisites_met_by?(current_user) }
                       .first(8)
  end

  def missions_user_already_has_a_project_on
    return [] unless current_user
    current_user.projects
                .where(deleted_at: nil)
                .joins(:mission_attachments)
                .where(project_mission_attachments: { detached_at: nil, deleted_at: nil })
                .pluck("project_mission_attachments.mission_id")
                .uniq
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
      track_event "project_created", { project_id: @project.id, source: "new_form" }
      flash[:notice] = "Project created successfully"

      project_hours = @project.total_hackatime_hours

      if (slug = params[:mission_slug].presence) && (mission = Mission.find_by(slug: slug)) && mission.prerequisites_met_by?(current_user)
        # A project created for a hardware mission is born hardware (design
        # stage) so it satisfies the mission's hardware-only requirement.
        @project.update!(hardware_stage: "design") if mission.hardware? && !@project.hardware?
        @project.missions << mission
        attrs = {}
        # Only fill in a mission's default name when the builder didn't give one
        # (older clients, or a create that skipped the name prompt).
        if @project.placeholder_title?
          attrs[:title] = mission.default_project_title.presence || mission.name
        end
        if @project.description.blank? && mission.default_project_description.present?
          attrs[:description] = mission.default_project_description
        end
        @project.update!(attrs) if attrs.any?
      end

      first_project = current_user.projects.count == 1
      redirect_to project_path(@project, first_project ? { welcome: 1 } : {})
    else
      flash[:alert] = "Failed to create project: #{@project.errors.full_messages.join(', ')}"
      @missions = Mission.available
                         .includes(:icon_attachment, :banner_attachment)
                         .order(featured_at: :desc)
                         .limit(8)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @project
    redirect_to project_path(@project, editing: true)
  end

  def update
    authorize @project

    whodunnit = impersonating? ? real_user&.id : current_user&.id
    success = nil

    PaperTrail.request(whodunnit: whodunnit) do
      @project.assign_attributes(project_params)
      validate_urls
      success = @project.errors.empty? && @project.save

      link_hackatime_projects if success
    end
    # 2nd check w/ @project.errors.empty? is not redudant. this is ensures that hackatime is linked!
    if success && @project.errors.empty?
      respond_to do |format|
        format.turbo_stream do
          if params[:return_to].present?
            flash[:notice] = "Project updated successfully"
            redirect_to url_from(params[:return_to])
          else
            flash.now[:notice] = "Project updated successfully"
            render turbo_stream: turbo_stream.update("flash-region", partial: "shared/flash")
          end
        end
        format.html do
          flash[:notice] = "Project updated successfully"
          redirect_to url_from(params[:return_to]) || project_path(@project)
        end
      end
    else
      respond_to do |format|
        format.turbo_stream do
          if params[:return_to].present?
            flash[:alert] = "Failed to update project: #{@project.errors.full_messages.join(', ')}"
            redirect_to url_from(params[:return_to])
          else
            flash.now[:alert] = "Failed to update project: #{@project.errors.full_messages.join(', ')}"
            render turbo_stream: turbo_stream.update("flash-region", partial: "shared/flash"), status: :unprocessable_entity
          end
        end
        format.html do
          flash[:alert] = "Failed to update project: #{@project.errors.full_messages.join(', ')}"
          redirect_to url_from(params[:return_to]) || edit_project_path(@project)
        end
      end
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
      flash[:notice] = "Project deleted successfully"
      redirect_to profile_projects_path(current_user.display_name)
    rescue ActiveRecord::RecordInvalid => e
      flash[:alert] = e.record.errors.full_messages.to_sentence
      redirect_to project_path(@project)
    end
  end

  def follow
    @project = Project.find(params[:id])
    authorize @project, :follow?

    follow = current_user.project_follows.build(project: @project)
    if follow.save
      @project.users.find_each do |member|
        Notifications::ProjectFollowed.notify(recipient: member, actor: current_user, record: @project)
      end
      redirect_to project_path(@project), notice: "You are now following this project."
    else
      redirect_to project_path(@project), alert: follow.errors.full_messages.to_sentence
    end
  end

  def unfollow
    @project = Project.find(params[:id])
    authorize @project, :follow?

    follow = current_user.project_follows.find_by(project: @project)
    if follow&.destroy
      redirect_to project_path(@project), notice: "You have unfollowed this project."
    else
      redirect_to project_path(@project), alert: "Could not unfollow."
    end
  end

  # /projects/latest — permalink to the newest project on Stardance.
  #
  # Ordered by created_at rather than updated_at: "latest" here means most
  # recently started, and updated_at churns on every edit, hour sync and
  # counter-cache bump, which would make the target jump around.
  #
  # Project's default_scope excludes soft-deleted records, so this can't land on
  # one. It's redirect-only, so the usual project-page authorization runs on the
  # target itself when show renders.
  def latest
    project = Project.order(created_at: :desc).first

    if project
      redirect_to project_path(project)
    else
      redirect_to root_path, alert: "There aren't any projects yet!"
    end
  end

  def followers
    @project = Project.find(params[:id])
    authorize @project, :show?
    @followers = @project.followers.where(banned: false).order(:display_name)
    render "users/followers", layout: false
  end

  def readme
    unless turbo_frame_request?
      redirect_to project_path(@project)
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

  def redirect_guest_owner_to_link!
    return unless current_user&.guest?
    return unless @project&.memberships&.exists?(user_id: current_user.id, role: :owner)

    redirect_to projects_setup_link_account_path, alert: "Finish setting up your account to keep working on your project."
  end

  # `project` is fetched rather than required so a create that arrives without it
  # (a client where the name prompt never opened) re-renders :new with a title
  # validation error instead of a bare 400.
  def project_params
    params.fetch(:project, ActionController::Parameters.new)
          .permit(:title, :description, :demo_url, :repo_url, :readme_url, :banner, :ai_declaration, :update_description, :hardware_stage, hackatime_project_ids: [])
  end

  def hackatime_project_ids
    @hackatime_project_ids ||= Array(params.dig(:project, :hackatime_project_ids)).reject(&:blank?).map(&:to_i)
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

  def validate_url_not_dead(attribute, name)
    require "uri"

    return unless @project.send(attribute).present?

    uri = URI.parse(@project.send(attribute))

    status = @project.url_probe_status(@project.send(attribute), cache: false)
    return if status.nil?

    unless (200..299).cover?(status)
      @project.errors.add(attribute, "Your #{name} needs to return a 200 status. I got #{status}, is your code/website set to public!?!?")
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

      path = uri.path.downcase.chomp("/")
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
  rescue SafeUrl::Error => e
    # Host failed SSRF verification (non-public IP, unresolvable, bad scheme).
    # Keep the real reason in the logs; give the user a cheeky generic message
    # so we don't confirm whether an internal host exists.
    Rails.logger.warn("URL validation rejected #{attribute}: #{e.message}")
    @project.errors.add(attribute, "nice try ding dong — #{name} has to be a real, public URL")
  rescue SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ECONNRESET,
         Errno::ETIMEDOUT, Errno::ENETUNREACH, Errno::EPIPE,
         Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
    Rails.logger.warn("URL validation failed for #{attribute}: #{e.class}: #{e.message}")
    @project.errors.add(attribute, "#{name} could not be reached. Please make sure the URL is valid and publicly accessible.")
  rescue StandardError => e
    Rails.logger.warn("URL validation error for #{attribute}: #{e.class}: #{e.message}")
    @project.errors.add(attribute, "#{name} could not be verified. Please try again or contact support if the issue persists.")
  end
  def link_hackatime_projects
    # Unlink hackatime projects that were removed. Scoped to the current user:
    # every member of a hardware project has their own row under the same name,
    # and the form only ever submits this user's ids.
    @project.hackatime_projects.where(user: current_user).where.not(id: hackatime_project_ids).find_each do |hp|
      unless hp.update(project: nil)
        hp.errors.full_messages.each do |message|
          @project.errors.add(:base, "Hackatime project #{hp.name}: #{message}")
        end
      end
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

  def test_time_session_key
    "test_time_project_#{@project.id}"
  end

  def test_time_hackatime_project_name
    "stardance-test-time-#{@project.id}"
  end
end
