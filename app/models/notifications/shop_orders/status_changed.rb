module Notifications
  module ShopOrders
    class StatusChanged < ::Notification
      self.aggregatable         = false
      self.category_key         = :shop_order_status_changed
      self.category_label       = "Shop order updates"
      self.category_description = "Your shop order moved to a new state"
      self.category_group       = "Shop"
      self.inbox_record_preloads = :shop_item

      STATE_CONFIG = {
        "rejected"                        => { priority: :high,     template: "rejected",                    headline: "was rejected" },
        "awaiting_verification"           => { priority: :high,     template: "awaiting_verification",       headline: "needs verification" },
        "awaiting_verification_call"      => { priority: :critical, template: "awaiting_verification_call",  headline: "needs a verification call" },
        "awaiting_periodical_fulfillment" => { priority: :medium,   template: "awaiting_fulfillment",        headline: "is queued for fulfillment" },
        "fulfilled"                       => { priority: :high,     template: "fulfilled",                   headline: "was fulfilled" }
      }.freeze

      DEFAULT_CONFIG = { priority: :medium, template: "default", headline: nil }.freeze

      def self.priority_for(state)
        STATE_CONFIG.fetch(state, DEFAULT_CONFIG)[:priority]
      end

      def self.template_for(state)
        "notifications/shop_orders/#{STATE_CONFIG.fetch(state, DEFAULT_CONFIG)[:template]}"
      end

      def headline
        state = params["state"].to_s
        config_headline = STATE_CONFIG.fetch(state, DEFAULT_CONFIG)[:headline]
        return config_headline if config_headline
        return "was updated" if state.blank?

        "moved to #{state.humanize}"
      end

      def slack_payload
        {
          message: nil,
          blocks_path: self.class.template_for(params["state"].to_s),
          locals: { order: record }
        }
      end

      def email_subject
        item = record&.shop_item&.name
        verb = headline
        item.present? ? "Your shop order for #{item} #{verb}" : "Your shop order #{verb}"
      end
    end
  end
end
