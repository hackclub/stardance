# frozen_string_literal: true

# The discover rail: a fixed right-hand column of composable widgets.
#
# Controllers declare which widgets appear and optionally hand them page
# context (see ApplicationController.discover_rail_widgets). Each named slug is
# resolved against the widget registry, built, and rendered — widgets decide
# for themselves whether they have anything to show.
#
#   render DiscoverRailComponent.new                       # widgets from the controller
#   render DiscoverRailComponent.new(widgets: [:dino])     # an explicit override
class DiscoverRailComponent < ViewComponent::Base
  def initialize(widgets: nil, user: nil, context: nil)
    @widget_slugs = widgets
    @user = user
    @context = context
  end

  def widgets
    @widgets ||= widget_slugs.filter_map { |slug| build_widget(slug) }
  end

  private

  def build_widget(slug)
    klass = DiscoverRail::BaseWidget.registry[slug.to_sym]
    klass&.new(user: user, context: context)
  end

  def widget_slugs
    Array(@widget_slugs || helpers.try(:discover_rail_widgets))
  end

  def user
    @user.nil? ? helpers.try(:current_user) : @user
  end

  def context
    @context || helpers.try(:discover_rail_context) || {}
  end
end
