class Admin::ViralityReviewsController < Admin::ApplicationController
  QUEUES = { "pending" => "Needs review", "on_hold" => "On hold", "scheduled" => "Scheduled", "reviewed" => "Reviewed" }.freeze
  SORTS = { "oldest" => "Oldest first", "flags" => "Most red flags", "newest" => "Newest", "most" => "Most mentions" }.freeze

  before_action :authorize_review

  def index
    @queue = queue_param
    @sort = params[:sort].presence_in(SORTS.keys) || "oldest"
    @search = params[:q].to_s.strip
    scheduled_ids = ViralityDecision.scheduled.pluck(:project_mention_id).to_set
    queues = queue_scopes(ViralityDecision.scheduled.select(:project_mention_id))
    @counts = queues.transform_values { |scope| scope.distinct.count(:project_id) }
    @awaiting_confirmation = queues["reviewed"].awaiting_review.count

    project_ids = searched(queues[@queue]).distinct.select(:project_id)
    reviews = Virality::ProjectReview.for(ProjectMention.where(project_id: project_ids).includes(:project).to_a, scheduled_ids: scheduled_ids)
    @pagy, @reviews = pagy(:offset, sorted(reviews), limit: 25)
    @undoable = ViralityDecision.scheduled.where(reviewer: current_user).includes(project_mention: :project).order(:process_at)
    @body_class = "app-layout-page"

    if params[:mention_id].present?
      @mention = ProjectMention.find(params[:mention_id])
      load_detail
    elsif (project = params[:project_id].present? ? Project.with_deleted.find(params[:project_id]) : @reviews.first&.project)
      @review = Virality::ProjectReview.new(project, project.mentions.to_a, scheduled_ids: scheduled_ids)
      load_project_detail
    end
  end

  def batch
    project = Project.with_deleted.find(params[:project_id])
    mentions = project.mentions.where(id: Array(params[:mention_ids])).order(:id).to_a
    operation = params[:operation].to_s
    Virality::BatchReview.new(
      project: project, mentions: mentions, reviewer: current_user, operation: operation,
      reason: params[:reason], internal_note: params[:internal_note],
      review_checklist: Array(params[:review_checklist]).compact_blank & ProjectMention::ELIGIBILITY_CHECKS,
      manual_override: params[:manual_override] == "1",
      evidence: params.fetch(:evidence, {}).permit(project.mentions.ids.to_h { |id| [ id.to_s, %i[platform metric_name metric_value tier] ] }).to_h
    ).call
    count = helpers.pluralize(mentions.size, "mention")
    if operation == "save"
      redirect_to admin_virality_reviews_path(queue: queue_param, project_id: project.id), notice: "Saved #{count}.", status: :see_other
    else
      notice = operation.in?(%w[approve reject]) ? "#{operation.humanize} scheduled for #{count}. You can stop each one before it processes." : "#{operation == 'hold' ? 'Put' : 'Released'} #{count} #{operation == 'hold' ? 'on hold' : 'from hold'}."
      redirect_to admin_virality_reviews_path(queue: queue_param), notice: notice, status: :see_other
    end
  rescue ArgumentError => error
    redirect_to admin_virality_reviews_path(queue: queue_param, project_id: params[:project_id]), alert: error.message, status: :see_other
  end

  def create
    mention = ProjectMention.find(params[:id])
    mention.triage!(triage_params) if params[:mention].present?
    attributes = decision_params.to_h
    attributes[:evidence] = attributes.fetch(:evidence, {}).merge(eligibility_confirmed: mention.eligibility_confirmed? ? "1" : "0")
    decision = ViralityDecision.schedule!(mention: mention, reviewer: current_user, attributes: attributes)
    # Reversals stay on the mention; approvals and rejections move straight to
    # the next submission, with the stop button in the undo bar.
    destination = decision.action == "reverse" ? { queue: "scheduled", mention_id: mention.id } : { queue: queue_param }
    redirect_to admin_virality_reviews_path(destination), notice: "#{decision.action.humanize} scheduled. You can stop it before it processes."
  rescue ActiveRecord::RecordInvalid, ArgumentError => error
    redirect_to admin_virality_reviews_path(queue: queue_param, mention_id: params[:id]), alert: error.message, status: :see_other
  end

  def triage
    mention = ProjectMention.find(params[:id])
    hold = params.dig(:mention, :on_hold)
    attributes = triage_params
    attributes[:on_hold_at] = (Time.current if hold == "1") unless hold.nil?
    dismissed = params.dig(:mention, :dismiss_proposal).present?
    attributes.merge!(proposed_action: nil, proposed_tier: nil) if dismissed
    mention.triage!(attributes)
    if hold.nil? && !dismissed
      redirect_to admin_virality_reviews_path(queue: queue_param, mention_id: mention.id), notice: "Notes saved.", status: :see_other
    else
      redirect_to admin_virality_reviews_path(queue: queue_param), notice: hold == "1" ? "Put on hold." : "Back in the review queue.", status: :see_other
    end
  rescue ActiveRecord::RecordInvalid, ArgumentError => error
    redirect_to admin_virality_reviews_path(queue: queue_param, mention_id: params[:id]), alert: error.message, status: :see_other
  end

  def cancel
    decision = ViralityDecision.find(params[:id])
    decision.cancel!(actor: current_user)
    redirect_to admin_virality_reviews_path(mention_id: decision.project_mention_id), notice: "Stopped. No decision or payout was applied.", status: :see_other
  rescue ArgumentError => error
    redirect_to admin_virality_reviews_path(queue: "scheduled"), alert: error.message, status: :see_other
  end

  def show
    decision = ViralityDecision.find(params[:id])
    render json: { status: decision.status, process_at: decision.process_at.iso8601, server_time: Time.current.iso8601,
                   destination: admin_virality_reviews_path(queue: decision.project_mention.status == :pending ? "pending" : "reviewed", mention_id: decision.project_mention_id) }
  end

  private

  def authorize_review
    authorize :virality_review
  end

  def queue_param
    params[:queue].presence_in(QUEUES.keys) || "pending"
  end

  def queue_scopes(scheduled_ids)
    {
      "pending" => ProjectMention.awaiting_review.unproposed.not_on_hold.where.not(id: scheduled_ids),
      "on_hold" => ProjectMention.awaiting_review.unproposed.on_hold.where.not(id: scheduled_ids),
      "scheduled" => ProjectMention.where(id: scheduled_ids),
      "reviewed" => ProjectMention.where.not(approved_at: nil).or(ProjectMention.where.not(rejected_at: nil)).or(ProjectMention.proposed).where.not(id: scheduled_ids)
    }
  end

  def searched(scope)
    return scope if @search.blank?

    term = "%#{ProjectMention.sanitize_sql_like(@search)}%"
    scope.joins(:project).where(
      "projects.title ILIKE :term OR project_mentions.url ILIKE :term OR project_mentions.submitter_notes ILIKE :term OR project_mentions.internal_notes ILIKE :term OR CAST(project_mentions.project_id AS text) = :id",
      term: term, id: @search
    )
  end

  def sorted(reviews)
    far_future = Time.zone.local(9999)
    reviews.sort_by do |review|
      proposed = review.counts["awaiting_confirmation"].to_i.positive? ? 0 : 1
      case @sort
      when "flags" then [ proposed, -review.red_flags, review.oldest_pending_at || far_future ]
      when "newest" then [ proposed, -review.newest_at.to_f ]
      when "most" then [ proposed, -review.mentions.size, review.oldest_pending_at || far_future ]
      else [ proposed, review.oldest_pending_at || far_future, review.project.id ]
      end
    end
  end

  def load_project_detail
    project = @review.project
    service = Virality::ReconcileBonus.new(project)
    @current_tier = service.tier
    @previews = {}
    @preview_errors = {}
    %w[good great].each do |tier|
      @previews[tier] = service.preview(tier: tier)
    rescue ArgumentError => error
      @preview_errors[tier] = error.message
    end
    @recipients = User.where(id: @previews.values.flat_map { |preview| preview[:changes].keys }).index_by(&:id)
    @project_links = { "Repo" => project.repo_url, "Demo" => project.demo_url, "README" => project.readme_url }
      .select { |_, url| url.to_s.match?(%r{\Ahttps?://}i) }
    @decisions = ViralityDecision.where(project_mention_id: @review.mentions.map(&:id)).includes(:reviewer, :project_mention).order(created_at: :desc)
  end

  def decision_params
    params.require(:decision).permit(:action, :tier, :reason, evidence: [ :platform, :metric_name, :metric_value, :manual_override ])
  end

  def triage_params
    attributes = params.fetch(:mention, {}).permit(:internal_notes, :extra_links, review_checklist: [])
    attributes[:review_checklist] = attributes[:review_checklist].compact_blank if attributes.key?(:review_checklist)
    attributes
  end

  def load_detail
    @decisions = @mention.virality_decisions.includes(:reviewer, :cancelled_by).order(created_at: :desc)
    @scheduled = @decisions.find { |decision| decision.status == "scheduled" }
    @siblings = @mention.project.mentions.where.not(id: @mention.id).order(:id)
    @project_links = { "Repo" => @mention.project.repo_url, "Demo" => @mention.project.demo_url, "README" => @mention.project.readme_url }
      .select { |_, url| url.to_s.match?(%r{\Ahttps?://}i) }
    @service = Virality::ReconcileBonus.new(@mention.project)
    @previews = {}
    @preview_errors = {}
    %w[good great reverse].each do |action|
      proposed_tier = @service.tier(excluding: @mention, adding: action == "reverse" ? nil : action)
      @previews[action] = @service.preview(tier: proposed_tier)
    rescue ArgumentError => error
      @preview_errors[action] = error.message
    end
    @recipients = User.where(id: @previews.values.flat_map { |preview| preview[:changes].keys }).index_by(&:id)
  end
end
