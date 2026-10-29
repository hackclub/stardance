module Notifications
  module ShopOrders
    # Sent when an admin adds or changes the carrier tracking on a shop order,
    # which often lands days after the order was marked fulfilled.
    class TrackingUpdated < ::Notification
      self.default_priority      = :high
      self.slack_template_path   = "notifications/shop_orders/tracking_updated"
      self.category_key          = :shop_order_tracking_updated
      self.category_label        = "Shop order tracking"
      self.category_description  = "Tracking for your shop order was added or changed"
      self.category_group        = "Shop"
      self.inbox_record_preloads = :shop_item
      # Slack and in-app only; the order page is where tracking lives.
      self.email_deliverable     = false

      # The number is taken from params rather than the order so the DM shows
      # what was set, even if it changes again before the DM job runs.
      def slack_locals
        { order: record, tracking_number: params["tracking_number"] }
      end
    end
  end
end
