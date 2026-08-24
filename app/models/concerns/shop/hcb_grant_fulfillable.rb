module Shop::HCBGrantFulfillable
  extend ActiveSupport::Concern

  # The HCB organizations a grant item may draw its card grant from. Blank means
  # the app-wide default (HCBService::DEFAULT_SLUG); "stardance-hardware" targets
  # the hardware sub-org, matching Certification::FundingRequest#issue_hcb_grant!.
  HCB_ORG_SLUGS = %w[stardance stardance-hardware].freeze

  included do
    has_many :shop_card_grants, through: :shop_orders
    after_save :enqueue_hcb_locks_update, if: :hcb_locks_changed?
    validates :hcb_org_slug, inclusion: { in: HCB_ORG_SLUGS }, allow_blank: true
  end

  def fulfill!(shop_order)
    ShopCardGrant.with_advisory_lock("hcb_grant_fulfill_#{shop_order.user_id}_#{id}", timeout_seconds: 15) do
      shop_order.reload
      return if shop_order.fulfilled?

      # The disbursement for this order already went through and only the state
      # change was lost. Finish the bookkeeping rather than paying again.
      if shop_order.shop_card_grant_id.present?
        shop_order.mark_fulfilled! "SCG #{shop_order.shop_card_grant_id}", nil, "System"
        return shop_order.shop_card_grant
      end

      fulfill_grant!(shop_order)
    end
  end

  private

  def fulfill_grant!(shop_order)
    amount_cents = (usd_cost * shop_order.quantity * 100).to_i
    grant_rec = ShopCardGrant.find_or_initialize_by(user: shop_order.user, shop_item: self)

    # A claimed row with no grant id means an earlier attempt called HCB and
    # never learned the outcome. Creating another grant here is how someone
    # gets paid twice, so stop and let a human reconcile it.
    if grant_rec.persisted? && grant_rec.hcb_grant_hashid.blank?
      raise HCBError, "ShopCardGrant ##{grant_rec.id} was claimed but never recorded a grant id. " \
                      "A grant may already exist on HCB; reconcile it by hand before retrying."
    end

    # A grant the recipient cancelled, or one HCB can no longer describe, can't
    # be topped up, so this order gets a fresh one.
    grant_rec = ShopCardGrant.new(user: shop_order.user, shop_item: self) if grant_rec.persisted? && !topupable?(grant_rec)

    memo, disbursement = if grant_rec.new_record?
      create_grant!(grant_rec, shop_order, amount_cents)
    else
      top_up_grant!(grant_rec, shop_order, amount_cents)
    end

    # Written before the state change on purpose: this is the record that the
    # money for this order already moved, and it is what the retry path above
    # reads to avoid a second disbursement.
    shop_order.update!(shop_card_grant: grant_rec)
    shop_order.mark_fulfilled! "SCG #{grant_rec.id}", nil, "System"
    rename_disbursement(disbursement, memo)

    grant_rec
  end

  def create_grant!(grant_rec, shop_order, amount_cents)
    email = shop_order.user.grant_email
    Rails.logger.info "Creating new #{amount_cents}¢ HCB #{grant_label} for #{email}"

    # Claimed before the call goes out, so a request whose outcome is unknown
    # leaves evidence behind instead of nothing at all.
    grant_rec.save!

    begin
      response = HCBService.create_card_grant(
        email: email,
        amount_cents: amount_cents,
        merchant_lock: hcb_merchant_lock,
        keyword_lock: hcb_keyword_lock,
        category_lock: hcb_category_lock,
        purpose: name,
        one_time_use: hcb_one_time_use?,
        organization: effective_hcb_org_slug,
        **extra_grant_options
      )
    rescue HCBError
      # HCB answered, so nothing was created. Drop the claim so the next
      # attempt starts clean instead of tripping the guard above.
      grant_rec.destroy
      raise
    end

    hashid = response["id"]
    # Logged before it is stored: if the write below is lost, this line is the
    # only trace of a grant that exists on HCB.
    Rails.logger.info "Created HCB grant #{hashid} for shop_card_grant=#{grant_rec.id}"
    grant_rec.update!(hcb_grant_hashid: hashid, expected_amount_cents: amount_cents)

    [ "[#{grant_label}] #{name} for #{shop_order.user.display_name}",
      response.dig("disbursements", 0, "transaction_id") ]
  end

  def top_up_grant!(grant_rec, shop_order, amount_cents)
    hashid = grant_rec.hcb_grant_hashid
    Rails.logger.info "Topping up #{hashid} by #{amount_cents}¢"

    response = HCBService.topup_card_grant(hashid: hashid, amount_cents: amount_cents)
    grant_rec.update!(expected_amount_cents: (grant_rec.expected_amount_cents || 0) + amount_cents)

    [ "[#{grant_label}] topping up #{shop_order.user.display_name}'s #{name}",
      response.dig("disbursements", 0, "transaction_id") ]
  end

  def topupable?(grant_rec)
    HCBService.show_card_grant(hashid: grant_rec.hcb_grant_hashid)["status"] != "canceled"
  rescue StandardError => e
    Rails.logger.error "Error checking grant status: #{e.message}"
    false
  end

  # Cosmetic, and never worth failing a disbursement that already landed.
  def rename_disbursement(disbursement, memo)
    return unless disbursement && memo

    HCBService.rename_transaction(hashid: disbursement, new_memo: memo)
  rescue StandardError => e
    Rails.logger.error "Couldn't rename transaction #{disbursement}: #{e.message}"
  end

  def grant_label = "grant"

  def extra_grant_options = {}

  # The org this item's card grant is drawn from, defaulting to the app-wide HCB
  # org when the admin hasn't chosen one.
  def effective_hcb_org_slug = hcb_org_slug.presence || HCBService::DEFAULT_SLUG

  def hcb_locks_changed?
    saved_change_to_hcb_merchant_lock? ||
      saved_change_to_hcb_keyword_lock? ||
      saved_change_to_hcb_category_lock?
  end

  def enqueue_hcb_locks_update
    Shop::UpdateHCBLocksJob.perform_later(id)
  end
end
