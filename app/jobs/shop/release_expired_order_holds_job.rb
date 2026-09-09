# frozen_string_literal: true

class Shop::ReleaseExpiredOrderHoldsJob < ApplicationJob
  queue_as :latency_10s

  WHODUNNIT = name.freeze

  def perform(now = Time.current)
    ShopOrder.expired_holds(now).find_each do |order|
      release_if_expired(order, now)
    end
  end

  private

  def release_if_expired(order, now)
    order.with_lock do
      return unless order.hold_expired?(now)

      PaperTrail.request(whodunnit: WHODUNNIT) do
        order.paper_trail_event = "automatic_hold_release"
        order.take_off_hold!
      end
    end
  end
end
