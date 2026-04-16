module TheseusService
    BASE_URL = "https://mail.hackclub.com"
    class << self
      def _conn
        @conn ||= Faraday.new url: "#{BASE_URL}".freeze do |faraday|
          faraday.request :json
          faraday.response :mashify
          faraday.response :json
          faraday.response :raise_error
          faraday.headers["Authorization"] = "Bearer #{Rails.application.credentials.theseus.api_key}".freeze
        end
      end

      def create_letter_v1(queue, data)
        _conn.post("/api/v1/letter_queues/#{queue}", data).body
      end

      def create_warehouse_order(data)
        _conn.post("/api/v1/warehouse_orders", data).body
      end

      def create_letter(shop_orders, queue:)
        shop_orders = Array(shop_orders)
        first_order = shop_orders.first

        item_quantities = shop_orders.group_by { |o| o.shop_item.name }
                                     .transform_values { |group| group.sum(&:quantity) }
        rubber_stamps = item_quantities.map { |name, qty| "#{qty}x #{name}" }.join("\n")

        coalesced_key = Digest::SHA256.hexdigest(shop_orders.map(&:id).sort.join("_"))[0, 16]

        response = create_letter_v1(queue, {
          recipient_email: first_order.user.email,
          address: first_order.frozen_address,
          rubber_stamps: rubber_stamps,
          idempotency_key: "stardance_letter_#{Rails.env}_#{coalesced_key}",
          metadata: {
            stardance_user_id: first_order.user_id,
            stardance_order_ids: shop_orders.map(&:id),
            items: shop_orders.map { |o| { shop_item_id: o.shop_item_id, name: o.shop_item.name, quantity: o.quantity } }
          }
        })
        response[:id] || response["id"]
      end

      def get_letter(letter_id)
        _conn.get("/api/v1/letters/#{letter_id}").body
      end
    end
end
