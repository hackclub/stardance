# frozen_string_literal: true

# T2 hardware queue: T1-approved submissions awaiting a second review before payout.
# The payout fires from Certification::SecondStageReview, so PaperTrail stays on the records.
class Admin::Certification::SecondStageReviewsController < Admin::Certification::ApplicationController
  include HardwareReviewRecordings

  before_action -> { head :not_found unless Flipper.enabled?(:hardware_t2_review) }
  before_action :set_review, only: [ :show, :update, :claim, :skip, :devlogs, :files ]
  before_action :set_body_class

  QUEUE_PAGE_SIZE = 25

  DEVLOG_GALLERY_LIMIT = 12

  def index
    authorize ::Certification::SecondStageReview
    redirect_to design_admin_certification_second_stage_reviews_path(
      params.permit(:status, :sort, :search).to_h.compact_blank
    )
  end

  def design
    load_queue(:design)
    render :queue
  end

  def build
    load_queue(:build)
    render :queue
  end

  def next
    authorize ::Certification::SecondStageReview
    release_other_claims

    stage = stage_param
    candidate = ::Certification::SecondStageReview.for_stage(stage).next_eligible(current_user)
    if candidate.nil?
      redirect_to queue_path_for(stage), notice: "The #{stage} T2 queue is empty." and return
    end

    claimed = ::Certification::SecondStageReview.atomic_claim!(candidate.id, current_user)
    if claimed
      redirect_to second_stage_path(claimed)
    else
      redirect_to next_admin_certification_second_stage_reviews_path(stage: stage)
    end
  end

  def claim
    authorize @review

    ::Certification::SecondStageReview.release_all_for(current_user)
    claimed = ::Certification::SecondStageReview.atomic_claim!(@review.id, current_user)
    if claimed
      redirect_to second_stage_path
    else
      redirect_to second_stage_path,
                  alert: "Couldn't claim that review, someone else got it."
    end
  end

  # Hides it from this reviewer for the cooldown; "next" releases the claim for others.
  def skip
    authorize @review

    ::Certification::ReviewSkip.record!(user: current_user, reviewable: @review) if @review.pending?
    redirect_to next_admin_certification_second_stage_reviews_path(stage: @review.stage)
  end

  def show
    authorize @review
    @reviewable = @review.reviewable
    @project = @reviewable.project
    @owner = @review.owner
    @first_stage_reviewer = @review.first_stage_reviewer
    @review_notes = @project.review_notes.includes(:author).newest_first
    @devlog_count = @project.devlog_posts.count
    load_undo_context

    @prior_reviews = (@project.certification_funding_requests.includes(:reviewer).to_a +
                      @project.ship_reviews.includes(:reviewer).to_a)
      .reject { |r| r == @reviewable }
      .select { |r| r.decided? || r.reversed_at.present? }
      .sort_by(&:created_at)
      .reverse
  end

  # Its own lazy frame: the recording services are network calls the verdict form mustn't wait on.
  def devlogs
    authorize @review, :show?

    @project = @review.reviewable.project
    @owner = @review.owner
    @order = params[:order] == "oldest" ? "oldest" : "newest"
    @devlog_count = @project.devlog_posts.count
    @devlogs = ordered_devlogs

    @lapse_owner_uid = @owner&.hackatime_identity&.uid
    @lapse_timelapses = lapse_timelapses_for(@project, @owner)
    @lookout_recordings = lookout_recordings_for(@project)

    windows = devlog_windows
    @devlog_lapses = ::Certification::DevlogRecordingBucketer.call(
      recordings: @lapse_timelapses, windows: windows
    )
    @devlog_lookouts = ::Certification::DevlogRecordingBucketer.call(
      recordings: @lookout_recordings, windows: windows
    )

    render :devlogs, layout: false
  end

  # Its own lazy frame too: two GitHub calls that mustn't delay the verdict form.
  def files
    authorize @review, :show?

    @project = @review.reviewable.project
    @filenames, @selected_path, @file_body = fetch_repo_files

    @file_tree = build_file_tree(@filenames)
    @open_dirs = @selected_path.to_s.split("/")[0..-2].each_with_object([]) do |segment, dirs|
      dirs << [ dirs.last, segment ].compact.join("/")
    end

    render :files, layout: false
  end

  def update
    authorize @review

    verdict = params.dig(:certification_second_stage_review, :verdict).to_s
    unless ::Certification::SecondStageReview::VERDICTS.include?(verdict)
      redirect_to second_stage_path,
                  alert: "Pick approve or return." and return
    end

    @review.assign_attributes(
      verdict: verdict,
      feedback: params.dig(:certification_second_stage_review, :feedback),
      internal_reason: params.dig(:certification_second_stage_review, :internal_reason)
    )

    # Only an approval of a grant T1 already funded can change the amount.
    if verdict == "approved" && @review.stage == "design" && @review.reviewable.issues_grant?
      @review.approved_amount_dollars =
        params.dig(:certification_second_stage_review, :approved_amount_dollars)
    end

    if @review.save
      # Attached after the save, or the photos would stick to a verdict that failed.
      images = params.dig(:certification_second_stage_review, :feedback_images)
      @review.feedback_images.attach(images.compact_blank) if images.present?

      redirect_to queue_path_for(@review.stage), notice: verdict_notice(@review)
    else
      redirect_to second_stage_path,
                  alert: @review.errors.full_messages.to_sentence
    end
  end

  private

  # Keyed by project: at most one stage is pending at a time; fall back to the newest decided one.
  def set_review
    scope = ::Certification::SecondStageReview.for_project(params[:project_id])
    @review = scope.pending.order(created_at: :desc).first ||
              scope.order(created_at: :desc).first
    raise ActiveRecord::RecordNotFound if @review.nil?
  end

  def ordered_devlogs
    scope = @project.devlogs.includes(:post, attachments_attachments: :blob).to_a
    scope.sort_by! { |d| d.post&.created_at || d.created_at }
    scope.reverse! if @order == "newest"
    scope.first(DEVLOG_GALLERY_LIMIT)
  end

  # Each devlog covers the time since the previous one (half-open, as DevlogRecordingBucketer expects).
  def devlog_windows
    posts = @project.devlog_posts.reorder("posts.created_at ASC").to_a
    posts.each_with_index.with_object({}) do |(post, idx), windows|
      since = idx.zero? ? @project.created_at : posts[idx - 1].created_at
      windows[post.postable_id] = { since: since.iso8601, before: post.created_at.iso8601 }
    end
  end

  # The preflight can call HCB, so it only runs for someone allowed to undo.
  def load_undo_context
    return unless Flipper.enabled?(:hardware_review_undo, current_user)
    return unless @reviewable.decided?

    policy_class = @reviewable.is_a?(::Certification::FundingRequest) ?
      Admin::Certification::FundingRequestPolicy : Admin::Certification::ShipPolicy
    return unless policy_class.new(current_user, @reviewable).undo?

    @undo_review = @reviewable
    @undo_preflight = ::Certification::ReviewUndoer.new(@reviewable).preflight
  end

  def undo_review_path(review)
    if review.is_a?(::Certification::FundingRequest)
      undo_admin_certification_funding_request_path(review)
    else
      undo_admin_certification_ship_path(review)
    end
  end
  helper_method :undo_review_path

  # Flat blob paths -> nested hashes (dirs) and full paths (files), folders first.
  def build_file_tree(paths)
    root = {}
    paths.each do |path|
      *dirs, name = path.split("/")
      node = dirs.reduce(root) { |current, dir| current[dir] ||= {} }
      node[name] = path
    end
    sort_file_tree(root)
  end

  def sort_file_tree(node)
    node.sort_by { |name, child| [ child.is_a?(Hash) ? 0 : 1, name.downcase ] }
        .to_h { |name, child| [ name, child.is_a?(Hash) ? sort_file_tree(child) : child ] }
  end

  # Only the GitHub calls are rescued: wrapping the whole action would swallow Pundit's denial.
  def fetch_repo_files
    return [ [], nil, nil ] if @project.repo_url.blank?

    host = ::GitHost::Base.for(@project.repo_url)
    names = (host&.fetch_filenames || []).sort
    @filenames = names
    selected = params[:path].presence_in(names) || default_readme
    [ names, selected, selected ? host&.fetch_file(selected) : nil ]
  rescue StandardError => e
    Rails.logger.error("T2 file browser failed for project #{@project&.id}: #{e.message}")
    [ [], nil, nil ]
  end

  # Prefers a root README over a deeper one.
  def default_readme
    @filenames
      .select { |name| File.basename(name).match?(/\Areadme(\.|\z)/i) }
      .min_by { |name| [ name.count("/"), name.length ] }
  end

  def second_stage_path(review = @review)
    admin_certification_second_stage_review_path(review.reviewable.project_id)
  end
  helper_method :second_stage_path

  def stage_param
    params[:stage].presence_in(%w[design build]) || "design"
  end

  def queue_path_for(stage)
    stage.to_s == "design" ?
      design_admin_certification_second_stage_reviews_path :
      build_admin_certification_second_stage_reviews_path
  end
  helper_method :queue_path_for

  def load_queue(stage)
    authorize ::Certification::SecondStageReview

    @stage = stage.to_s
    @status = params[:status].presence_in(%w[pending approved returned all]) || "pending"
    @sort = params[:sort] == "newest" ? "newest" : "oldest"
    @search = params[:search].to_s.strip

    scope = policy_scope(::Certification::SecondStageReview).for_stage(@stage)
    scope = scope.where(status: @status) unless @status == "all"
    scope = apply_search(scope)
    scope = scope.order(created_at: @sort == "newest" ? :desc : :asc)

    @pagy, @reviews = pagy(scope, limit: QUEUE_PAGE_SIZE)
    @tab_counts = tab_counts
  end

  # In SQL so pagy's counts stay right; matched per concrete table since reviewable is polymorphic.
  def apply_search(scope)
    return scope if @search.blank?

    like = "%#{@search}%"
    funding_ids = ::Certification::FundingRequest.joins(:project)
      .where("projects.title ILIKE ?", like).select(:id)
    ship_ids = ::Certification::Ship.joins(:project)
      .where("projects.title ILIKE ?", like).select(:id)

    scope.where(
      "(reviewable_type = 'Certification::FundingRequest' AND reviewable_id IN (:funding)) OR " \
      "(reviewable_type = 'Certification::Ship' AND reviewable_id IN (:ships))",
      funding: funding_ids, ships: ship_ids
    )
  end

  def tab_counts
    scope = policy_scope(::Certification::SecondStageReview)
    {
      "design" => scope.design_stage.pending.count,
      "build" => scope.build_stage.pending.count
    }
  end

  def release_other_claims
    return if current_user.blank?

    ::Certification::SecondStageReview.release_all_for(current_user)
  end

  def verdict_notice(review)
    if review.approved?
      review.stage == "design" ?
        "Cleared. The grant is on its way and the project has moved to the build stage." :
        "Cleared. The build is certified."
    else
      "Returned to the builder."
    end
  end

  # The .app-layout wrapper reserves the sidebar gutter itself; this body class
  # zeroes the body's own sidebar margin so the two don't stack into a huge gap.
  def set_body_class
    @body_class = "app-layout-page"
  end
end
