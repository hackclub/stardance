class Admin::Certification::IntegrityController < Admin::Certification::ApplicationController
  include FraudSubjectVerdict

  def index
    authorize :integrity, policy_class: Admin::Certification::IntegrityPolicy

    reviews = ::Certification::Integrity
      .pending
      .unclaimed_or_claimed_by(current_user)
      .joins(ship_event: :project)
      .includes(ship_event: [ :project, { post: :user } ])
      .order("projects.id ASC")
      .to_a

    @total_pending = reviews.size
    all_flags = ::Certification::Integrity::FLAGS_BY_BIT.values

    # Flags actually present across the queue, in canonical bit order — drives
    # the filter pills so we don't show a pill nobody can match.
    @available_flags = all_flags & reviews.flat_map(&:flag_names).uniq

    # Selected flags come from ?flags[]=. No param means the default "all
    # selected" view; an explicitly empty list (flags[]=) means none selected.
    @selected_flags =
      if params.key?(:flags)
        Array(params[:flags]).map(&:to_sym) & all_flags
      else
        @available_flags
      end

    # OR semantics: a review shows when it has no flags, or when any of its
    # flags is currently selected.
    @reviews = reviews.select do |review|
      names = review.flag_names
      names.empty? || names.intersect?(@selected_flags)
    end
  end

  def show
    @review = ::Certification::Integrity.find(params[:id])
    authorize @review, policy_class: Admin::Certification::IntegrityPolicy

    # Claim this review for the current admin so it drops off everyone else's
    # queue. Already-decided reviews (reached via history links) are read-only
    # and aren't claimed.
    if @review.pending?
      claimed = ::Certification::Integrity.atomic_claim!(@review.id, current_user)
      if claimed.nil?
        redirect_to admin_certification_integrity_reviews_path, alert: "This review is currently claimed by another admin."
        return
      end
      @review.claimed_by_id = claimed.claimed_by_id
      @review.claimed_at = claimed.claimed_at
    end

    @shop_orders = @review.user&.shop_orders&.includes(:shop_item)&.order(created_at: :desc) || ShopOrder.none
  end

  # Records a reviewer's verdict on a pending review. Only the admin currently
  # holding the claim can decide it, so two reviewers can't clobber each other.
  # PaperTrail (whodunnit set in Admin::ApplicationController) captures the audit
  # trail for the status change.
  def update
    @review = ::Certification::Integrity.find(params[:id])
    authorize @review, policy_class: Admin::Certification::IntegrityPolicy

    # A verdict from the per-person fraud page has never opened the review, so
    # it takes the claim here. atomic_claim! only succeeds when nobody else is
    # holding it, so this can't jump another reviewer's claim.
    if fraud_subject && @review.pending?
      ::Certification::Integrity.atomic_claim!(@review.id, current_user)
      @review.reload
    end

    unless @review.pending? && @review.claimed_by?(current_user)
      message = "This review can no longer be decided, it may have been claimed by another admin or already resolved."
      return render_fraud_subject_integrity_error(message) if fraud_subject

      redirect_to admin_certification_integrity_reviews_path, alert: message
      return
    end

    case params[:decision]
    when "pass"
      @review.assign_attributes(status: :manually_passed, deduction_minutes: nil)
    when "fraud"
      @review.assign_attributes(status: :banned, deduction_minutes: nil)
    when "deduct"
      @review.assign_attributes(status: :deducted, deduction_minutes: deduction_minutes_param)
    else
      redirect_to admin_certification_integrity_review_path(@review), alert: "Unknown decision."
      return
    end

    @review.reviewer = current_user
    @review.decision_justification = params[:decision_justification].presence

    if @review.save
      if fraud_subject
        return render_fraud_subject_verdict(@review, "Recorded decision for review ##{@review.id}.",
                                            refresh_integrity: @review.status.in?(::Certification::Integrity::CASCADING_STATUSES))
      end

      redirect_to admin_certification_integrity_reviews_path,
                  notice: "Recorded decision for review ##{@review.id}."
    else
      errors = @review.errors.full_messages.to_sentence
      return render_fraud_subject_integrity_error(errors) if fraud_subject

      @shop_orders = @review.user&.shop_orders&.includes(:shop_item)&.order(created_at: :desc) || ShopOrder.none
      flash.now[:alert] = errors
      render :show, status: :unprocessable_entity
    end
  end

  private

  # A verdict from the fraud subject page is answering into that check's turbo
  # frame, so every failure has to come back as the frame too. Redirecting or
  # rendering the review page leaves the reviewer looking at "Content missing".
  def render_fraud_subject_integrity_error(message)
    @review.reload

    render turbo_stream: turbo_stream.replace(
      ActionView::RecordIdentifier.dom_id(@review),
      partial: "admin/fraud/subjects/integrity_check",
      locals: { check: @review, user: fraud_subject, error: message }
    ), status: :unprocessable_entity
  end

  # The "Deducted hours" verdict is entered in hours for the reviewer but stored
  # as whole minutes. Blank stays nil so the model's presence validation surfaces
  # the error instead of silently deducting zero.
  def deduction_minutes_param
    hours = params[:deduction_hours]
    return nil if hours.blank?

    (hours.to_f * 60).round
  end
end
