# frozen_string_literal: true

# The `undo` action shared by the funding-request and ship-certification review
# controllers. Both reverse a decided review through Certification::ReviewUndoer;
# each host controller only has to name the record via `review_for_undo`.
#
# Runs inside Admin::Certification::ApplicationController, so PaperTrail's
# whodunnit and the admin Pundit namespace are already wired up.
module HardwareReviewUndoable
  extend ActiveSupport::Concern

  def undo
    review = review_for_undo
    authorize review, :undo?

    path = hardware_review_path_for(review.project)
    result = ::Certification::ReviewUndoer.new(review, actor: current_user).undo!

    if result.undone?
      Rails.logger.info "[HardwareReview#undo] user=#{current_user&.id} #{review.class}=#{review.id} reversed to pending"
      redirect_to path, notice: undo_success_notice(result)
    else
      redirect_to path, alert: result.blocker_summary.presence || "That review can no longer be undone."
    end
  rescue Pundit::NotAuthorizedError
    raise
  rescue StandardError => e
    Rails.logger.error "[HardwareReview#undo] user=#{current_user&.id} review=#{params[:id]} #{e.class}: #{e.message}"
    Sentry.capture_exception(e, tags: { category: "certification.hardware" }, extra: { review_id: params[:id], user_id: current_user&.id })
    redirect_back fallback_location: admin_root_path, alert: "Failed to undo the review: #{e.message}"
  end

  private

  def undo_success_notice(result)
    notice = "Review reversed — it's back in the pending queue."
    manual = result.manual_steps
    notice += " Still needs a hand: #{manual.map(&:detail).join(' ')}" if manual.any?
    notice
  end
end
