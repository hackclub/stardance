module Shop::HCBGrantFulfillable
  extend ActiveSupport::Concern

  included do
    has_many :shop_card_grants, through: :shop_orders
    after_save :enqueue_hcb_locks_update, if: :hcb_locks_changed?
  end

  def fulfill!(shop_order)
    ShopCardGrant.with_advisory_lock("hcb_grant_fulfill_#{shop_order.user_id}_#{id}", timeout_seconds: 15) do
      shop_order.reload
      return if shop_order.fulfilled?

      fulfill_grant!(shop_order)
    end
  end

  private

  def fulfill_grant!(shop_order)
    amount_cents = (usd_cost * shop_order.quantity * 100).to_i
    email = shop_order.user.grant_email

    grant_rec = ShopCardGrant.find_or_initialize_by(
      user: shop_order.user,
      shop_item: self
    )

    user_canceled = false
    latest_disbursement = nil
    memo = nil

    grant_rec.transaction do
      begin
        if grant_rec.new_record? || user_canceled
          Rails.logger.info "Creating new #{amount_cents}¢ HCB #{grant_label} for #{email}"

          grant_res = HCBService.create_card_grant(
            email: email,
            amount_cents: amount_cents,
            merchant_lock: hcb_merchant_lock,
            keyword_lock: hcb_keyword_lock,
            category_lock: hcb_category_lock,
            purpose: name,
            one_time_use: hcb_one_time_use?,
            **extra_grant_options
          )

          grant_rec.hcb_grant_hashid = grant_res["id"]
          grant_rec.expected_amount_cents = amount_cents
          grant_rec.save!

          latest_disbursement = grant_res.dig("disbursements", 0, "transaction_id")
          memo = "[#{grant_label}] #{name} for #{shop_order.user.display_name}"
        else
          hashid = grant_rec.hcb_grant_hashid

          begin
            hcb_grant = HCBService.show_card_grant(hashid: hashid)
            if hcb_grant["status"] == "canceled"
              user_canceled = true
              raise StandardError, "Grant canceled"
            end
          rescue => e
            Rails.logger.error "Error checking grant status: #{e.message}"
            user_canceled = true
            raise StandardError, "Grant canceled"
          end

          Rails.logger.info "Topping up #{hashid} by #{amount_cents}¢"
          topup_res = HCBService.topup_card_grant(hashid: hashid, amount_cents: amount_cents)

          latest_disbursement = topup_res.dig("disbursements", 0, "transaction_id")
          grant_rec.expected_amount_cents = (grant_rec.expected_amount_cents || 0) + amount_cents
          grant_rec.save!

          memo = "[#{grant_label}] topping up #{shop_order.user.display_name}'s #{name}"
        end

        Rails.logger.info "Got disbursement #{latest_disbursement}"
      rescue => e
        if user_canceled
          Rails.logger.info "Grant was canceled, creating new grant"
          grant_rec = ShopCardGrant.new(user: shop_order.user, shop_item: self)
          user_canceled = false
          retry
        else
          raise e
        end
      end
    end

    shop_order.mark_fulfilled! "SCG #{grant_rec.id}", nil, "System"
    shop_order.update!(shop_card_grant: grant_rec)

    if latest_disbursement && memo
      begin
        HCBService.rename_transaction(hashid: latest_disbursement, new_memo: memo)
      rescue => e
        Rails.logger.error "Couldn't rename transaction #{latest_disbursement}: #{e.message}"
      end
    end

    grant_rec
  end

  def grant_label = "grant"

  def extra_grant_options = {}

  def hcb_locks_changed?
    saved_change_to_hcb_merchant_lock? ||
      saved_change_to_hcb_keyword_lock? ||
      saved_change_to_hcb_category_lock?
  end

  def enqueue_hcb_locks_update
    Shop::UpdateHCBLocksJob.perform_later(id)
  end
end
