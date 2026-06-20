class Api::V1::Users::Me::ShopRegionController < Api::BaseController
  include ApiAuthenticatable

  def update
    region = params[:region].to_s.upcase
    unless Shop::Regionalizable::REGION_CODES.include?(region)
      return render json: { error: "Invalid region code", request_id: request.request_id }, status: :unprocessable_entity
    end

    current_api_user.update_column(:shop_region, region)
    render json: { shop_region: region }
  end
end
