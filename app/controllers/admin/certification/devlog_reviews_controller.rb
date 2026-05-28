class Admin::Certification::DevlogReviewsController < Admin::Certification::ApplicationController
  def update
    devlog_review = ::Certification::Devlog.find(params[:id])
    authorize devlog_review

    if devlog_review.update(devlog_review_params)
      render json: {
        success: true,
        devlog_review: {
          id: devlog_review.id,
          status: devlog_review.status,
          approved_minutes: devlog_review.approved_minutes,
          justification: devlog_review.justification
        }
      }
    else
      render json: {
        success: false,
        errors: devlog_review.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  private

  def devlog_review_params
    params.require(:devlog_review).permit(:approved_minutes, :status, :justification)
  end
end
