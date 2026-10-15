class Admin::Shop::LetterMailBatchesController < Admin::ApplicationController
  def create
    authorize ShopOrder, :update?

    pending = ShopOrder.joins(:shop_item)
                       .where(shop_items: { type: Shop::ProcessLetterMailOrdersJob::LETTER_TYPES })
                       .where(aasm_state: "awaiting_periodical_fulfillment")
                       .count

    if pending.zero?
      redirect_to admin_shop_orders_path(view: "fulfillment"), alert: "No letter mail orders awaiting fulfillment." and return
    end

    Shop::ProcessLetterMailOrdersJob.perform_later
    redirect_to admin_shop_orders_path(view: "fulfillment"), notice: "Batching #{pending} letter mail #{"order".pluralize(pending)} into envelopes…"
  end
end
