class Admin::ShopOrdersController < Admin::ApplicationController
  before_action :set_paper_trail_whodunnit
  def index
    # Determine view mode
    @view = params[:view] || "shop_orders"
    @limit = params[:limit] || "10"

    # Fulfillment team can only access fulfillment view - auto-redirect if needed
    # But fraud_dept members with fulfillment_person role should have full access
    if current_user.shop_manager? && !current_user.admin?
      authorize :admin, :view_shop_orders_no_pii?
    elsif current_user.fulfillment_person? && !current_user.admin? && !current_user.fraud_dept?
      if @view != "fulfillment"
        redirect_to admin_shop_orders_path(view: "fulfillment") and return
      end
      authorize :admin, :access_fulfillment_view?
    else
      authorize :admin, :access_shop_orders?
    end

    # Load fulfillment users for assignment dropdown (admins and fulfillment peeps, fulfillment view)
    if (current_user.admin? || current_user.fulfillment_person?) && @view == "fulfillment"
      @fulfillment_users = User.where("'fulfillment_person' = ANY(granted_roles)").order(:display_name)
    end

    # Base query
    orders = ShopOrder.includes(:shop_item, :user, :accessory_orders, :assigned_to_user)

    # Apply status filter first if explicitly set (takes priority over view)
    if params[:status].present?
      orders = orders.where(aasm_state: params[:status])
    else
      # Apply view-specific scopes only if no explicit status filter
      case @view
      when "shop_orders"
        # Show pending, awaiting_verification, rejected, on_hold
        orders = orders.where(aasm_state: %w[pending awaiting_verification awaiting_verification_call rejected on_hold])
      when "fulfillment"
        # Show awaiting_periodical_fulfillment and fulfilled
        orders = orders.where(aasm_state: %w[awaiting_periodical_fulfillment fulfilled])
      end

      # Set default status for fraud dept
      @default_status = "pending" if current_user.fraud_dept? && !current_user.admin?
      orders = orders.where(aasm_state: @default_status) if @default_status.present?
    end

    # Apply shared filters to both the orders query and the stats base query
    orders = apply_shared_filters(orders)
    base = apply_shared_filters(ShopOrder.includes(:shop_item, :user))

    @c = {
      pending: base.where(aasm_state: "pending").count,
      awaiting_verification: base.where(aasm_state: "awaiting_verification").count,
      awaiting_verification_call: base.where(aasm_state: "awaiting_verification_call").count,
      awaiting_fulfillment: base.where(aasm_state: "awaiting_periodical_fulfillment").count,
      fulfilled: base.where(aasm_state: "fulfilled").count,
      rejected: base.where(aasm_state: "rejected").count,
      on_hold: base.where(aasm_state: "on_hold").count
    }

    # Calculate average times
    fulfilled_orders = base.where(aasm_state: "fulfilled").where.not(fulfilled_at: nil)
    if fulfilled_orders.any?
      @f = fulfilled_orders.average("EXTRACT(EPOCH FROM (shop_orders.fulfilled_at - shop_orders.created_at))").to_f
    end

    # Sorting - always uses database ordering now
    orders = case params[:sort]
    when "id_asc" then orders.order(id: :asc)
    when "id_desc" then orders.order(id: :desc)
    when "created_at_asc" then orders.order(created_at: :asc)
    when "shells_asc" then orders.order(frozen_item_price: :asc)
    when "shells_desc" then orders.order(frozen_item_price: :desc)
    else orders.order(created_at: :desc)
    end

    # Grouping
    if params[:goob] == "true"
      @grouped_orders = orders.group_by(&:user).map do |user, user_orders|
        {
          user: user,
          orders: user_orders,
          total_items: user_orders.sum(&:quantity),
          total_shells: user_orders.sum { |o| o.total_cost || 0 },
          address: user_orders.first&.decrypted_address_for(current_user)
        }
      end.sort_by { |g| -g[:orders].size }
    else
      @pagy, @shop_orders = pagy(:offset, orders, limit: 50)
    end
  end

  def show
    if current_user.shop_manager? && !current_user.admin?
      authorize :admin, :view_shop_orders_no_pii?
    elsif current_user.fulfillment_person? && !current_user.admin? && !current_user.fraud_dept?
      authorize :admin, :access_fulfillment_view?
    else
      authorize :admin, :access_shop_orders?
    end
    @order = ShopOrder.find(params[:id])

    # Fulfillment persons can only view orders in their regions, assigned to them, or with nil region
    if current_user.fulfillment_person? && !current_user.admin? && !current_user.fraud_dept?
      can_access = @order.assigned_to_user_id == current_user.id
      can_access ||= @order.region.nil?
      can_access ||= current_user.has_regions? && current_user.has_region?(@order.region)

      unless can_access
        redirect_to admin_shop_orders_path(view: "fulfillment"), alert: "You don't have access to this order" and return
      end
    end

    @can_view_address = @order.can_view_address?(current_user)
    @can_view_address = false if current_user.shop_manager? && !current_user.admin?
    @is_digital_fulfillment_type = ShopOrder::DIGITAL_FULFILLMENT_TYPES.include?(@order.shop_item.type)

    # Track who is viewing this order (cache-based presence)
    viewer_cache_key = "shop_order_viewers:#{@order.id}"
    viewers = Rails.cache.read(viewer_cache_key) || {}
    viewers.reject! { |_uid, ts| ts < 2.minutes.ago }
    @other_viewers = User.where(id: viewers.keys.reject { |uid| uid == current_user.id }).pluck(:display_name)
    viewers[current_user.id] = Time.current
    Rails.cache.write(viewer_cache_key, viewers, expires_in: 5.minutes)
    # Load fulfillment users for assignment (admins and fulfillment peeps)
    if current_user.admin? || current_user.fulfillment_person?
      @fulfillment_users = User.where("'fulfillment_person' = ANY(granted_roles)").order(:display_name)
    end

    # Load user's order history for fraud dept or order review
    @user_orders = @order.user.shop_orders.where.not(id: @order.id).order(created_at: :desc).limit(10)

    # Find sibling LetterMail orders for Theseus coalesce button
    if @order.shop_item.type == "ShopItem::LetterMail" && @order.awaiting_periodical_fulfillment?
      @theseus_sibling_orders = ShopOrder.joins(:shop_item)
                                         .where(shop_items: { type: "ShopItem::LetterMail" })
                                         .where(user_id: @order.user_id, frozen_address_ciphertext: @order.frozen_address_ciphertext)
                                         .where(aasm_state: "awaiting_periodical_fulfillment")
                                         .where.not(id: @order.id)
    end

    # User's shop orders summary stats
    user_orders = @order.user.shop_orders
    @user_order_stats = {
      total: user_orders.count,
      fulfilled: user_orders.where(aasm_state: "fulfilled").count,
      pending: user_orders.where(aasm_state: "pending").count,
      rejected: user_orders.where(aasm_state: "rejected").count,
      total_quantity: user_orders.sum(:quantity),
      on_hold: user_orders.where(aasm_state: "on_hold").count,
      awaiting_fulfillment: user_orders.where(aasm_state: "awaiting_periodical_fulfillment").count
    }
  end

  def reveal_address
    if current_user.fulfillment_person? && !current_user.admin? && !current_user.fraud_dept?
      authorize :admin, :access_fulfillment_view?
    else
      authorize :admin, :access_shop_orders?
    end
    @order = ShopOrder.find(params[:id])

    if @order.can_view_address?(current_user)
      @decrypted_address = @order.decrypted_address_for(current_user)

      PaperTrail::Version.create!(
        item_type: "User",
        item_id: @order.user_id,
        event: "address_revealed",
        whodunnit: current_user.id.to_s,
        object_changes: { order_id: @order.id, shop_item: @order.shop_item&.name }
      )

      render turbo_stream: turbo_stream.replace(
        "address-content",
        partial: "address_details",
        locals: { address: @decrypted_address, user_email: User.find(@order.user_id)&.email }
      )
    else
      render plain: "Unauthorized", status: :forbidden
    end
  end

  def reveal_phone
    if current_user.fulfillment_person? && !current_user.admin? && !current_user.fraud_dept?
      authorize :admin, :access_fulfillment_view?
    else
      authorize :admin, :access_shop_orders?
    end
    @order = ShopOrder.find(params[:id])

    if @order.can_view_address?(current_user)
      decrypted_address = @order.decrypted_address_for(current_user)
      phone_number = decrypted_address&.dig("phone_number")

      PaperTrail::Version.create!(
        item_type: "User",
        item_id: @order.user_id,
        event: "phone_revealed",
        whodunnit: current_user.id.to_s,
        object_changes: { order_id: @order.id, shop_item: @order.shop_item&.name }
      )

      render turbo_stream: turbo_stream.replace(
        "phone-content",
        html: "<div class='info-rows'><div><b>Phone:</b> #{phone_number.present? ? ERB::Util.html_escape(phone_number) : 'N/A'}</div></div><div style='margin-top: 1em; padding: 0.5em; background: #fef3c7; border-radius: 4px;'><small style='color: #92400e;'>🔒 Phone access has been logged for security purposes.</small></div>".html_safe
      )
    else
      render plain: "Unauthorized", status: :forbidden
    end
  end

  def approve
    authorize :admin, :access_shop_orders?
    @order = ShopOrder.find(params[:id])

    if @order.user_id == current_user.id
      redirect_to admin_shop_order_path(@order), alert: "You cannot approve your own order." and return
    end

    unless @order.pending? || @order.awaiting_verification_call?
      redirect_to admin_shop_order_path(@order), alert: "This order has already been processed." and return
    end

    if @order.requires_additional_review?
      redirect_to admin_shop_order_path(@order), alert: "This is a high-value order and requires 2 fraud dept reviews before approval (#{@order.reviews.count}/2 so far)." and return
    end

    old_state = @order.aasm_state

    if @order.shop_item.respond_to?(:fulfill!)
      @order.approve!
      redirect_to shop_orders_return_path, notice: "Order approved and fulfilled" and return
    end

    tracking_number = params[:tracking_number].presence

    if @order.shop_item.requires_verification_call?
      success = @order.queue_for_verification_call && @order.save
      notice = "Order queued for verification call"
    else
      if tracking_number.present?
        @order.tracking_number = tracking_number
      end
      success = @order.queue_for_fulfillment && @order.save
      notice = "Order approved for fulfillment"
    end

    if success
      PaperTrail::Version.create!(
        item_type: "ShopOrder",
        item_id: @order.id,
        event: "update",
        whodunnit: current_user.id,
        object_changes: {
          aasm_state: [ old_state, @order.aasm_state ]
        }
      )
      redirect_to shop_orders_return_path, notice: notice
    else
      redirect_to admin_shop_order_path(@order), alert: "Failed to approve order: #{@order.errors.full_messages.join(', ')}"
    end
  end

  def review_order
    authorize :admin, :access_shop_orders?
    @order = ShopOrder.find(params[:id])

    if !current_user.admin? && @order.user_id == current_user.id
      redirect_to admin_shop_order_path(@order), alert: "You cannot review your own order." and return
    end

    success = false
    notice_message = nil
    alert_message = nil

    @order.with_lock do
      previous_review_count = @order.reviews.count

      review = @order.reviews.build(
        user: current_user,
        verdict: params[:verdict],
        reason: params[:review_reason]
      )

      if review.save
        new_review_count = previous_review_count + 1

        PaperTrail::Version.create!(
          item_type: "ShopOrder",
          item_id: @order.id,
          event: "review",
          whodunnit: current_user.id,
          object_changes: {
            review_count: [ previous_review_count, new_review_count ],
            verdict: review.verdict,
            reason: review.reason
          }
        )

        success = true
        notice_message = "Review submitted — #{review.verdict} (#{new_review_count}/2)."
      else
        alert_message = review.errors.full_messages.to_sentence
      end
    end

    if success
      redirect_to admin_shop_order_path(@order), notice: notice_message
    else
      redirect_to admin_shop_order_path(@order), alert: alert_message
    end
  end

  def reject
    authorize :admin, :reject_shop_order?
    @order = ShopOrder.find(params[:id])

    if @order.requires_additional_review?
      redirect_to admin_shop_order_path(@order), alert: "This is a high-value order and requires 2 fraud dept reviews before rejection (#{@order.reviews.count}/2 so far)." and return
    end

    reason = params[:reason].presence || "No reason provided"

    if current_user.fraud_dept?
      internal_reason = params[:internal_rejection_reason]
      joe_case_url = params[:joe_case_url]
      fraud_project_id = params[:fraud_related_project_id]
    else
      internal_reason = reason
      joe_case_url = nil
      fraud_project_id = 1
    end
    old_state = @order.aasm_state

    @order.internal_rejection_reason = internal_reason
    @order.joe_case_url = joe_case_url.presence
    @order.fraud_related_project_id = fraud_project_id.presence

    if @order.mark_rejected(reason) && @order.save
      PaperTrail::Version.create!(
        item_type: "ShopOrder",
        item_id: @order.id,
        event: "update",
        whodunnit: current_user.id,
        object_changes: {
          aasm_state: [ old_state, @order.aasm_state ],
          rejection_reason: [ nil, reason ],
          internal_rejection_reason: [ nil, internal_reason ],
          joe_case_url: [ nil, joe_case_url.presence ],
          fraud_related_project_id: [ nil, fraud_project_id.presence ]
        }.compact_blank
      )

      n = @order.accessory_orders.select(&:may_mark_rejected?).count { |a|
        old = a.aasm_state
        a.internal_rejection_reason = internal_reason
        a.joe_case_url = joe_case_url.presence
        a.fraud_related_project_id = fraud_project_id.presence
        next unless a.mark_rejected(reason) && a.save
        PaperTrail::Version.create!(
          item_type: "ShopOrder", item_id: a.id, event: "update", whodunnit: current_user.id,
          object_changes: { aasm_state: [ old, a.aasm_state ], rejection_reason: [ nil, reason ], parent_order_cancelled: [ nil, @order.id ] }
        )
      }

      notice = "Order rejected"
      notice += " (#{n} #{'accessory'.pluralize(n)} also rejected)" if n > 0
      redirect_to shop_orders_return_path, notice: notice
    else
      redirect_to admin_shop_order_path(@order), alert: "Failed to reject order: #{@order.errors.full_messages.join(', ')}"
    end
  end

  def place_on_hold
    authorize :admin, :access_shop_orders?
    @order = ShopOrder.find(params[:id])
    old_state = @order.aasm_state

    if @order.place_on_hold && @order.save
      PaperTrail::Version.create!(
        item_type: "ShopOrder",
        item_id: @order.id,
        event: "update",
        whodunnit: current_user.id,
        object_changes: {
          aasm_state: [ old_state, @order.aasm_state ]
        }
      )
      redirect_to shop_orders_return_path, notice: "Order placed on hold"
    else
      redirect_to admin_shop_order_path(@order), alert: "Failed to place order on hold: #{@order.errors.full_messages.join(', ')}"
    end
  end

  def release_from_hold
    authorize :admin, :access_shop_orders?
    @order = ShopOrder.find(params[:id])
    old_state = @order.aasm_state

    if @order.take_off_hold && @order.save
      PaperTrail::Version.create!(
        item_type: "ShopOrder",
        item_id: @order.id,
        event: "update",
        whodunnit: current_user.id,
        object_changes: {
          aasm_state: [ old_state, @order.aasm_state ]
        }
      )
      redirect_to shop_orders_return_path, notice: "Order released from hold"
    else
      redirect_to admin_shop_order_path(@order), alert: "Failed to release order from hold: #{@order.errors.full_messages.join(', ')}"
    end
  end

  def mark_fulfilled
    if current_user.fulfillment_person? && !current_user.admin? && !current_user.fraud_dept?
      authorize :admin, :access_fulfillment_view?
    else
      authorize :admin, :access_shop_orders?
    end
    @order = ShopOrder.find(params[:id])

    if @order.shop_item.requires_verification_call? && !current_user.admin? && !@order.awaiting_periodical_fulfillment?
      redirect_to admin_shop_order_path(@order), alert: "Only admins can fulfill verification-call items" and return
    end

    old_state = @order.aasm_state

    if @order.mark_fulfilled(params[:external_ref].presence, params[:fulfillment_cost].presence, current_user.display_name) && @order.save
      PaperTrail::Version.create!(
        item_type: "ShopOrder",
        item_id: @order.id,
        event: "update",
        whodunnit: current_user.id,
        object_changes: {
          aasm_state: [ old_state, @order.aasm_state ]
        }
      )
      redirect_to admin_shop_order_path(@order), notice: "Order marked as fulfilled"
    else
      redirect_to admin_shop_order_path(@order), alert: "Failed to mark order as fulfilled: #{@order.errors.full_messages.join(', ')}"
    end
  end

  def update_internal_notes
    if current_user.fulfillment_person? && !current_user.admin? && !current_user.fraud_dept?
      authorize :admin, :access_fulfillment_view?
    else
      authorize :admin, :access_shop_orders?
    end
    @order = ShopOrder.find(params[:id])
    old_notes = @order.internal_notes

    if @order.update(internal_notes: params[:internal_notes])
      PaperTrail::Version.create!(
        item_type: "ShopOrder",
        item_id: @order.id,
        event: "update",
        whodunnit: current_user.id,
        object_changes: {
          internal_notes: [ old_notes, @order.internal_notes ]
        }
      )
      redirect_to admin_shop_order_path(@order), notice: "Internal notes updated"
    else
      redirect_to admin_shop_order_path(@order), alert: "Failed to update notes"
    end
  end

  def assign_user
    authorize :admin, :assign_shop_order?
    @order = ShopOrder.find(params[:id])
    old_assigned = @order.assigned_to_user_id

    new_assigned_id = params[:assigned_to_user_id].presence
    assigned_user = new_assigned_id ? User.find_by(id: new_assigned_id) : nil

    if @order.update(assigned_to_user_id: new_assigned_id)
      PaperTrail::Version.create!(
        item_type: "ShopOrder",
        item_id: @order.id,
        event: "assignment_updated",
        whodunnit: current_user.id,
        object_changes: {
          assigned_to_user_id: [ old_assigned, @order.assigned_to_user_id ]
        }
      )

      redirect_back fallback_location: admin_shop_order_path(@order), notice: "Order assigned to #{assigned_user&.display_name || 'nobody'}"
    else
      redirect_back fallback_location: admin_shop_order_path(@order), alert: "Failed to assign order"
    end
  end

  def approve_verification_call
    authorize :admin, :manage_shop?
    @order = ShopOrder.find(params[:id])
    old_state = @order.aasm_state

    unless @order.awaiting_verification_call?
      redirect_to shop_orders_return_path, alert: "Order cannot be approved because it is not currently awaiting a verification call." and return
    end

    if @order.queue_for_fulfillment && @order.save
      PaperTrail::Version.create!(
        item_type: "ShopOrder",
        item_id: @order.id,
        event: "update",
        whodunnit: current_user.id,
        object_changes: {
          aasm_state: [ old_state, @order.aasm_state ]
        }
      )
      redirect_to shop_orders_return_path, notice: "Order approved for fulfillment, thanks for verifying they are legit amber :3"
    else
      redirect_to admin_shop_order_path(@order), alert: "Failed to approve order: #{@order.errors.full_messages.join(', ')}"
    end
  end

  def cancel_hcb_grant
    authorize :admin, :manage_users?
    @order = ShopOrder.find(params[:id])

    unless @order.shop_card_grant.present?
      redirect_to admin_shop_order_path(@order), alert: "This order has no HCB grant to cancel"
      return
    end

    grant = @order.shop_card_grant
    begin
      HCBService.cancel_card_grant!(hashid: grant.hcb_grant_hashid)

      PaperTrail::Version.create!(
        item_type: "ShopOrder",
        item_id: @order.id,
        event: "hcb_grant_canceled",
        whodunnit: current_user.id,
        object_changes: { hcb_grant_hashid: grant.hcb_grant_hashid, canceled_by: current_user.display_name }.to_json
      )

      redirect_to admin_shop_order_path(@order), notice: "HCB grant canceled successfully"
    rescue => e
      redirect_to admin_shop_order_path(@order), alert: "Failed to cancel HCB grant: #{e.message}"
    end
  end
  private

  def apply_shared_filters(scope)
    scope = scope.where(shop_item_id: params[:shop_item_id]) if params[:shop_item_id].present?
    scope = scope.where("created_at >= ?", params[:date_from]) if params[:date_from].present?
    scope = scope.where("created_at <= ?", params[:date_to]) if params[:date_to].present?

    if params[:user_search].present?
      search = "%#{ActiveRecord::Base.sanitize_sql_like(params[:user_search])}%"
      scope = scope.joins(:user).where("users.display_name ILIKE ? OR users.email ILIKE ? OR users.id::text = ? OR users.slack_id ILIKE ?", search, search, params[:user_search], search)
    end

    if params[:assignee_ids].present?
      selected_ids = Array(params[:assignee_ids]).map(&:to_s)
      has_unassigned = selected_ids.include?("unassigned")
      user_ids = selected_ids.reject { |id| id == "unassigned" }.map(&:to_i)

      if has_unassigned && user_ids.any?
        scope = scope.where(assigned_to_user_id: nil).or(scope.where(assigned_to_user_id: user_ids))
      elsif has_unassigned
        scope = scope.where(assigned_to_user_id: nil)
      elsif user_ids.any?
        scope = scope.where(assigned_to_user_id: user_ids)
      end
    end

    if current_user.fulfillment_person? && !current_user.admin? && !current_user.fraud_dept? && current_user.has_regions?
      scope = scope.where(region: current_user.regions)
                   .or(scope.where(region: nil))
                   .or(scope.where(assigned_to_user_id: current_user.id))
    elsif params[:region].present?
      scope = scope.where(region: params[:region].upcase)
    end

    scope
  end

  def shop_orders_return_path
    # Preserve the view and status params for redirecting back to the list
    params_to_keep = {}
    params_to_keep[:view] = params[:return_view] if params[:return_view].present?
    params_to_keep[:status] = params[:return_status] if params[:return_status].present?
    admin_shop_orders_path(params_to_keep)
  end

  public

  def send_to_theseus
    authorize :admin, :access_shop_orders?
    @order = ShopOrder.find(params[:id])

    order_ids = (Array(params[:order_ids]).map(&:to_i) | [ @order.id ]).uniq

    @order.user.with_advisory_lock("theseus_send", timeout_seconds: 10) do
      orders_to_send = ShopOrder.joins(:shop_item)
                                .where(id: order_ids, shop_items: { type: "ShopItem::LetterMail" }, aasm_state: "awaiting_periodical_fulfillment")
                                .to_a

      stale_ids = order_ids - orders_to_send.map(&:id)
      if stale_ids.any?
        redirect_to admin_shop_order_path(@order), alert: "Order(s) #{stale_ids.join(', ')} no longer awaiting fulfillment. Please refresh and try again." and return
      end

      letter_id = TheseusService.create_letter(orders_to_send, queue: "stardance-envelope")
      orders_to_send.each { |o| o.mark_fulfilled!(letter_id, nil, "#{current_user.display_name} - Letter Mail (Theseus)") }

      notice = "Sent to Theseus (letter #{letter_id})"
      notice += " — #{orders_to_send.size} orders coalesced" if orders_to_send.size > 1
      redirect_to admin_shop_order_path(@order), notice: notice
    rescue => e
      redirect_to admin_shop_order_path(@order), alert: "Failed to send to Theseus: #{e.message}"
    end
  end

  def refresh_verification
    authorize :admin, :access_shop_orders?
    @order = ShopOrder.find(params[:id])

    unless @order.awaiting_verification?
      redirect_to admin_shop_order_path(@order), alert: "Order is not awaiting verification" and return
    end

    user = @order.user
    identity = user.identities.find_by(provider: "hack_club")

    unless identity&.access_token.present?
      redirect_to admin_shop_order_path(@order), alert: "User has no Hack Club identity token" and return
    end

    payload = HCAService.identity(identity.access_token)
    if payload.blank?
      redirect_to admin_shop_order_path(@order), alert: "Could not fetch verification status from HCA" and return
    end

    status = payload["verification_status"].to_s
    ysws_eligible = payload["ysws_eligible"] == true

    old_status = user.verification_status
    user.verification_status = status if User.verification_statuses.key?(status)
    user.ysws_eligible = ysws_eligible
    user.save!

    PaperTrail::Version.create!(
      item_type: "ShopOrder",
      item_id: @order.id,
      event: "verification_refreshed",
      whodunnit: current_user.id,
      object_changes: {
        user_verification_status: [ old_status, user.verification_status ],
        ysws_eligible: [ !ysws_eligible, ysws_eligible ]
      }
    )

    if user.eligible_for_shop?
      Shop::ProcessVerifiedOrdersJob.perform_later(user.id)
      redirect_to admin_shop_order_path(@order), notice: "User is now verified. Processing orders..."
    elsif user.should_reject_orders?
      user.reject_awaiting_verification_orders!
      redirect_to admin_shop_order_path(@order), notice: "User verification failed. Orders rejected."
    else
      redirect_to admin_shop_order_path(@order), notice: "Verification status updated to: #{user.verification_status}"
    end
  rescue StandardError => e
    Rails.logger.error "Failed to refresh verification status for order #{@order.id}: #{e.message}"
    redirect_to admin_shop_order_path(@order), alert: "Error refreshing verification: #{e.message}"
  end

  def force_state
    authorize :admin, :manage_shop?
    @order = ShopOrder.find(params[:id])

    old_state = @order.aasm_state
    new_state = params[:target_state]

    unless ShopOrder.aasm.states.map { |s| s.name.to_s }.include?(new_state)
      redirect_to admin_shop_order_path(@order), alert: "Invalid state."
      return
    end

    if old_state == new_state
      redirect_to admin_shop_order_path(@order), alert: "Order is already #{new_state}."
      return
    end

    @order.update_column(:aasm_state, new_state)

    PaperTrail::Version.create!(
      item: @order,
      event: "update",
      whodunnit: current_user.id.to_s,
      object_changes: { aasm_state: [ old_state, new_state ] }
    )

    redirect_to admin_shop_order_path(@order), notice: "State forced from #{old_state} to #{new_state}."
  end
end
