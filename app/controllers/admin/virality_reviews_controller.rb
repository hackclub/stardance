class Admin::ViralityReviewsController < Admin::ApplicationController
  before_action :authorize_review

  def index
    @queue = params[:queue].in?(%w[pending scheduled reviewed]) ? params[:queue] : "pending"
    scheduled_ids = ViralityDecision.scheduled.select(:project_mention_id)
    @counts = {
      "pending" => ProjectMention.awaiting_review.where.not(id: scheduled_ids).count,
      "scheduled" => ProjectMention.where(id: scheduled_ids).count,
      "reviewed" => ProjectMention.where.not(approved_at: nil).or(ProjectMention.where.not(rejected_at: nil)).where.not(id: scheduled_ids).count
    }
    mentions = ProjectMention.includes(:project).order(created_at: :asc, id: :asc)
    mentions = case @queue
    when "scheduled" then mentions.where(id: scheduled_ids)
    when "reviewed" then mentions.where.not(approved_at: nil).or(mentions.where.not(rejected_at: nil)).where.not(id: scheduled_ids)
    else mentions.awaiting_review.where.not(id: scheduled_ids)
    end
    @pagy, @mentions = pagy(:offset, mentions, limit: 25)
    @mention = params[:mention_id].present? ? ProjectMention.find(params[:mention_id]) : @mentions.first
    load_detail if @mention
    @body_class = "app-layout-page"
  end

  def create
    mention = ProjectMention.find(params[:id])
    decision = ViralityDecision.schedule!(mention: mention, reviewer: current_user, attributes: decision_params.to_h)
    redirect_to admin_virality_reviews_path(queue: "scheduled", mention_id: mention.id), notice: "#{decision.action.humanize} scheduled. You can stop it before it processes."
  rescue ActiveRecord::RecordInvalid, ArgumentError => error
    redirect_to admin_virality_reviews_path(mention_id: params[:id]), alert: error.message, status: :see_other
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

  def decision_params
    params.require(:decision).permit(:action, :tier, :reason, evidence: [ :platform, :metric_name, :metric_value, :eligibility_confirmed, :manual_override ])
  end

  def load_detail
    @decisions = @mention.virality_decisions.includes(:reviewer, :cancelled_by).order(created_at: :desc)
    @scheduled = @decisions.find { |decision| decision.status == "scheduled" }
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
