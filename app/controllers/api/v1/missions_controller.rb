class Api::V1::MissionsController < Api::BaseController
  include ApiAuthenticatable

  def index
    return unless (limit = api_limit)

    missions = Mission.enabled
                      .with_attached_icon
                      .with_attached_banner
                      .order(featured_at: :desc, name: :asc)

    @pagy, @missions = pagy(missions, limit: limit)
  end

  def show
    @mission = Mission.enabled
                      .with_attached_icon
                      .with_attached_banner
                      .find_by!(slug: params[:slug])

    @steps  = @mission.steps.where(deleted_at: nil).ordered
    @prizes = @mission.prizes.ordered.includes(shop_item: { image_attachment: :blob })
  end
end
