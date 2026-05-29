# frozen_string_literal: true

module DiscoverRail
  # Base class for every card that can appear in the discover rail.
  #
  # A widget claims a slug, controllers compose a rail by naming slugs (see
  # ApplicationController.discover_rail_widgets), and the rail looks each one up
  # here. Subclassing and registering is the whole contract:
  #
  #   class PopularProjectsWidget < DiscoverRail::BaseWidget
  #     register_as :popular_projects
  #
  #     def render?
  #       projects.any?
  #     end
  #   end
  #
  # The rail builds each widget with `new(user:, context:)` and leans on
  # ViewComponent's own `render?` gate, so a data-backed widget can quietly bow
  # out on a pageload where it has nothing worth showing.
  class BaseWidget < ViewComponent::Base
    # slug (Symbol) => widget class. Populated by `register_as`; read by
    # DiscoverRailComponent. Reassigned rather than mutated so the inherited
    # default is never shared across subclasses.
    class_attribute :registry, default: {}, instance_accessor: false

    def self.register_as(slug)
      BaseWidget.registry = BaseWidget.registry.merge(slug.to_sym => self)
    end

    attr_reader :user, :context

    def initialize(user: nil, context: {})
      @user = user
      @context = context || {}
    end
  end
end
