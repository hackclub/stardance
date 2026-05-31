# frozen_string_literal: true

module Feed
  class ShelfComponent < ViewComponent::Base
    renders_many :items

    attr_reader :title, :href, :items_collection

    def initialize(title:, items:, href: nil)
      @title = title
      @items_collection = items
      @href = href
    end

    def render?
      items_collection.any?
    end
  end
end
