# "Resources" is the public-facing name for the Guides catalog (the sidebar
# links guides_path under the "resources" label). Guides are static value
# objects (Guide.all), so there is nothing to paginate or persist.
class Api::V1::ResourcesController < Api::BaseController
  include ApiAuthenticatable

  def index
    @resources = Guide.all
  end

  def show
    @resource = Guide.find_by_slug(params[:id])
    raise ActiveRecord::RecordNotFound if @resource.nil?
  end
end
