# Takes back the stardust a ship paid for hours a fraud reviewer judged bad.
# Separate from the review's own "deduct hours" verdict, which cuts the hours
# off the certificate rather than the balance, so a reviewer can do either.
class Admin::Certification::Integrity::DeductionsController < Admin::Certification::ApplicationController
  include FraudSubjectVerdict

  def create
    @review = ::Certification::Integrity.find(params[:integrity_id])
    authorize @review, :update?, policy_class: Admin::Certification::IntegrityPolicy

    @recipient = @review.ship_event.payout_recipient
    return render_deduction(error: "This ship has nobody to deduct from.") if @recipient.nil?

    authorize @recipient, :adjust_balance?

    error = deduction_error
    return render_deduction(error: error) if error

    entry = @review.deduct_stardust!(hours: hours_param, reason: reason_param, actor: current_user)
    render_deduction(notice: "Deducted #{entry.amount.abs} stardust from #{@recipient.display_name}.")
  end

  private

  def hours_param = params[:hours].to_f

  def reason_param = params[:reason].to_s.strip

  def deduction_error
    return "Hours must be more than zero." unless hours_param.positive?
    return "A reason is required." if reason_param.blank?
    return "That comes to no stardust at this rate." if @review.deduction_stardust_for(hours_param).zero?

    nil
  end

  # From the fraud page the check stays in the queue, so its row is re-rendered
  # in place with the outcome. The balance the deduction just moved is up in the
  # identity panel, which would otherwise still read the old figure.
  def render_deduction(notice: nil, error: nil)
    unless fraud_subject
      return redirect_to admin_certification_integrity_review_path(@review), notice: notice, alert: error
    end

    render turbo_stream: [
      turbo_stream.replace(
        ActionView::RecordIdentifier.dom_id(@review),
        partial: "admin/fraud/subjects/integrity_check",
        locals: { check: @review, user: fraud_subject, notice: notice, error: error }
      ),
      turbo_stream.replace(
        "fraud-subject-identity-panel",
        partial: "admin/fraud/subjects/identity",
        locals: { user: fraud_subject }
      )
    ]
  end
end
