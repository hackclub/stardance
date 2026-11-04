class Admin::Certification::PermanentRejectionNominationsController < Admin::Certification::ApplicationController
  before_action -> { @body_class = "app-layout-page" }
  before_action :set_nomination, only: [ :show, :approve, :deny, :undo ]

  def index
    authorize ::Certification::PermanentRejectionNomination
    @status = params[:status].presence_in(::Certification::PermanentRejectionNomination.statuses.keys) || "pending"
    @pending_count = ::Certification::PermanentRejectionNomination.pending.count
    @pagy, @nominations = pagy(:offset, ::Certification::PermanentRejectionNomination
      .where(status: @status).includes(:project, :reviewer, :decided_by)
      .order(created_at: :asc), limit: 25)
  end

  def show
    authorize @nomination
  end

  def create
    review = case params[:review_type]
    when "funding" then ::Certification::FundingRequest.find(params[:review_id])
    when "ship" then ::Certification::Ship.find(params[:review_id])
    else raise ActiveRecord::RecordNotFound
    end
    @nomination = ::Certification::PermanentRejectionNomination.new(project: review.project, reviewable: review)
    authorize @nomination
    @nomination = ::Certification::PermanentRejectionNomination.nominate!(
      review: review, reviewer: current_user, reason: params[:reason]
    )
    notice = if @nomination.approved?
      "Project permanently rejected. The builder will receive the explanation through their review notifications."
    else
      "Nominated for permanent rejection and removed from the review queue. The builder has not been notified."
    end
    redirect_to hardware_review_next_path_for(review.project, @nomination.review_stage.downcase), notice: notice
  rescue ActiveRecord::RecordInvalid => e
    @nomination = e.record
    render :new, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::StaleObjectError
    redirect_to hardware_review_path_for(review.project), alert: "This review changed. Reload it before trying again."
  end

  def approve
    authorize @nomination
    decide(approve: true)
  end

  def deny
    authorize @nomination
    decide(approve: false)
  end

  def undo
    authorize @nomination
    redirect_path = if params[:redirect_to_hardware].present?
      hardware_review_path_for(@nomination.project)
    else
      admin_certification_permanent_rejection_nomination_path(@nomination)
    end
    @nomination.undo!(admin: current_user)
    redirect_to redirect_path,
      notice: "Permanent rejection undone. The submission is back in its original queue and the builder will receive a correction."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to redirect_path, alert: e.record.errors.full_messages.to_sentence
  end

  private

  def set_nomination
    @nomination = ::Certification::PermanentRejectionNomination.includes(:project, :reviewer, :decided_by, :reviewable).find(params[:id])
  end

  def decide(approve:)
    @nomination.decide!(admin: current_user, approve: approve)
    redirect_to admin_certification_permanent_rejection_nomination_path(@nomination), notice: approve ?
      "Permanent rejection approved. The builder will receive the explanation through their review notifications." :
      "Nomination denied. The submission is back in its original queue. Nothing was sent to the builder."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to admin_certification_permanent_rejection_nomination_path(@nomination), alert: e.record.errors.full_messages.to_sentence
  end
end
