class Api::V1::MACAnalysesController < Api::V1::BaseController
  include Pagy::Method

  def pending
    scope = Certification::Ysws.pending
                               .without_mac_analysis
                               .order(created_at: :asc)

    pagy = Pagy::Offset.new(count: scope.count, page: params[:page] || 1)

    review_ids = scope.offset(pagy.offset)
                      .limit(pagy.limit)
                      .pluck(:id)

    render json: { review_ids:, page: pagy.page, pages: pagy.pages, count: pagy.count }
  end

  def create
    review = Certification::Ysws.find(params.require(:review_id))

    analysis = review.mac_analysis || review.build_mac_analysis
    analysis.report = params.require(:report)
    analysis.generated_at = params[:generated_at] || Time.current

    if analysis.save
      render json: { id: analysis.id }, status: :ok
    else
      render json: { errors: analysis.errors.full_messages }, status: :unprocessable_entity
    end
  end

  alias_method :update, :create

  private

    def credential_api_keys
      Array.wrap(Rails.application.credentials.dig(:mac_analysis, :api_key) || ENV["MAC_ANALYSIS_API_KEY"])
    end
end
