# == Schema Information
#
# Table name: shop_warehouse_packages
#
#  id                        :bigint           not null, primary key
#  frozen_address_ciphertext :text
#  frozen_contents           :jsonb
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  theseus_package_id        :string
#  user_id                   :bigint           not null
#
# Indexes
#
#  index_shop_warehouse_packages_on_theseus_package_id  (theseus_package_id) UNIQUE
#  index_shop_warehouse_packages_on_user_id             (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
#  fk_rails_...  (user_id => users.id)

class ShopWarehousePackage < ApplicationRecord
  has_encrypted :frozen_address, type: :json

  belongs_to :user
  has_many :shop_orders, foreign_key: :warehouse_package_id, dependent: :nullify

  validates :frozen_address, presence: true
  validates :theseus_package_id, uniqueness: true, allow_nil: true

  BONUS_STICKER_COUNT = 3

  def send_to_theseus!
    return theseus_package_id if theseus_package_id.present? && !theseus_package_id.start_with?("MANUAL_FIX_NEEDED_")

    if user.email.blank? || frozen_address.blank?
      Rails.logger.warn(
        "ShopWarehousePackage #{id} missing email or address — skipping"
      )
      return
    end

    headline = []

    contents = shop_orders.includes(:shop_item).flat_map do |order|
      headline << order.shop_item.name
      item_contents = order.get_agh_contents

      if item_contents.blank? && order.shop_item.is_a?(ShopItem::WarehouseItem)
        raise ArgumentError, "Shop item '#{order.shop_item.name}' (ID: #{order.shop_item.id}) is missing valid AGH contents. Please update the item's AGH Contents field with valid JSON."
      end

      item_contents
    end

    contents += bonus_stickers
    contents << {
      sku: "Pri/Fla/4x6/1st",
      quantity: 2
    }
    update!(frozen_contents: contents)
    Rails.logger.info "Sending warehouse package #{id} to Theseus for user #{user_id} with orders #{shop_orders.pluck(:id).join(', ')}\nContents: #{contents.inspect}"

    order_ids = shop_orders.order(:id).pluck(:id).join("-")
    idempotency_key = "stardance_warehouse_package_#{Rails.env}_#{user_id}_#{order_ids}"

    retries = 0
    begin
      response = TheseusService.create_warehouse_order({
                                                         address: frozen_address.compact_blank,
                                                         contents: contents,
                                                         tags: [ "stardance", "YSWS", "stardance-warehouse-prize" ],
                                                         recipient_email: user.email,
                                                         user_facing_title: "Stardance - #{headline.join ', '}",
                                                         idempotency_key:,
                                                         metadata: {
                                                           stardance_user: user.id,
                                                           orders: shop_orders.map do |order|
                                                             {
                                                               id: order.id,
                                                               item_name: order.shop_item.name,
                                                               quantity: order.quantity
                                                             }
                                                           end
                                                         }
                                                       })
      theseus_id = response.dig("warehouse_order", "id")
      raise "Theseus response missing warehouse_order.id for package #{id}" if theseus_id.blank?

      Rails.logger.info "Successfully sent warehouse package #{id} to Theseus with Theseus package ID #{theseus_id}"
      update!(theseus_package_id: theseus_id)
    rescue Faraday::SSLError => e
      retries += 1
      if retries <= 3
        Rails.logger.warn "SSL error sending pkg #{id} to Theseus (atmpt #{retries})! #{e.message}. Retrying"
        sleep(retries * 2)
        retry
      else
        Rails.logger.error "Failed to send pkg #{id} to Theseus after 3 tries. #{e.message}"
        raise
      end
    rescue Faraday::BadRequestError => e
      body = e.response&.dig(:body)

      is_idempotency_error = false
      if body.is_a?(String)
        begin
          parsed = JSON.parse(body)
          is_idempotency_error = parsed["error"] == "idempotency_error"
        rescue JSON::ParserError
          # whoops i guess it wasn't json
        end
      end

      if is_idempotency_error
        Rails.logger.error "Idempotency error sending pkg #{id} to Theseus. Package created on Theseus but we don't have the ID."
        SendSlackDmJob.perform_later(
          "U054VC2KM9P", # hardcoded to amber
          "Idempotency error sending warehouse package #{id} to Theseus. Package was created on Theseus but we don't have the ID. You need to manually fix this."
        )
        update!(theseus_package_id: "MANUAL_FIX_NEEDED_#{idempotency_key}")
        return
      end

      Rails.logger.error "Failed to send pkg #{id} to Theseus: #{e.message}"
      raise

    rescue => e
      Rails.logger.error "Failed to send pkg #{id} to Theseus: #{e.message}"
      Rails.logger.error e.response&.dig(:body) if e.respond_to?(:response) && e.response&.dig(:body)
      raise
    end
  end

  private

  def bonus_stickers
    pile_of_stickers_item = ShopItem::PileOfStickersItem.find_by(enabled: true)
    return [] unless pile_of_stickers_item&.agh_contents&.dig("choice").present?

    possible_stickers = pile_of_stickers_item.agh_contents["choice"]
    possible_stickers.shuffle.take(BONUS_STICKER_COUNT).map do |sku|
      { sku:, quantity: 1 }
    end
  end
end
