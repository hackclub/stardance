class GuidesController < ApplicationController
  discover_rail_widgets :upcoming_events

  before_action :set_body_class

  def index
    @guides_by_category = Guide.by_category
    @category_order = Guide.category_order
  end

  def show
    @guide = Guide.find_by_slug(params[:id])
    raise ActiveRecord::RecordNotFound if @guide.nil?
  end

  private

  def set_body_class
    @body_class = "app-layout-page guides-page"
  end
end
