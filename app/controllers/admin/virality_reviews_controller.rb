class Admin::ViralityReviewsController < Admin::ApplicationController
  QUEUES = { "pending" => "Needs review", "on_hold" => "On hold", "scheduled" => "Scheduled", "reviewed" => "Reviewed" }.freeze

  before_action :authorize_review

  def index
    @queue = queue_param
    scheduled_ids = ViralityDecision.scheduled.select(:project_mention_id)
    queues = {
      "pending" => ProjectMention.awaiting_review.unproposed.not_on_hold.where.not(id: scheduled_ids),
      "on_hold" => ProjectMention.awaiting_review.unproposed.on_hold.where.not(id: scheduled_ids),
      "scheduled" => ProjectMention.where(id: scheduled_ids),
      "reviewed" => ProjectMention.where.not(approved_at: nil).or(ProjectMention.where.not(rejected_at: nil)).or(ProjectMention.proposed).where.not(id: scheduled_ids)
    }
    @counts = queues.transform_values(&:count)
    @awaiting_confirmation = queues["reviewed"].awaiting_review.count
    # Imported verdicts waiting for confirmation sort first, so confirming one
    # lands on the next.
    mentions = queues[@queue].includes(:project).order(Arel.sql("project_mentions.proposed_action IS NULL"), created_at: :asc, id: :asc)
    @pagy, @mentions = pagy(:offset, mentions, limit: 25)
    @mention = params[:mention_id].present? ? ProjectMention.find(params[:mention_id]) : @mentions.first
    @undoable = ViralityDecision.scheduled.where(reviewer: current_user).includes(project_mention: :project).order(:process_at)
    load_detail if @mention
    @body_class = "app-layout-page"
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
