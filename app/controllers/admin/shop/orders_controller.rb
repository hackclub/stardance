class Admin::Shop::OrdersController < Admin::ApplicationController
  before_action :set_paper_trail_whodunnit
  before_action :set_order, except: [ :index, :bulk_approve ]

  # Filter/search params that should survive navigation between the status
  # chips, the group-by-user toggle, and pagination. Centralised here so the
  # views don't each repeat (and risk drifting from) the permit list.
  PRESERVED_FILTER_KEYS = [
    :user_search, :shop_item_id, :status, :date_from, :date_to, :sort, :view,
    :goob, :region, :item_type, :min_tickets, :max_tickets, :has_tracking,
    :order_type, { assignee_ids: [], hidden_types: [] }
  ].freeze

  # TutorialNothing is never fulfilled by a human, so it's dropped from the
  # queue outright rather than given a toggle nobody would reach for.
  ALWAYS_HIDDEN_ITEM_TYPES = %w[ShopItem::TutorialNothing].freeze

  # Item-type groups the fulfillment queue can fold away, one toggle each.
  # FreeStickers needs no human work and WarehouseItem is fulfilled by the
  # external warehouse, so those start folded away. Mail is packed by hand and
  # stays visible — HQ mail and letter mail share a single toggle because
  # they're worked as one pile. New LetterMail subclasses join the mail group
  # through ShopItem::LetterMail::TYPES, so they fold with the rest of it.
  # Sticky Streak stickers get their own toggle rather than folding in with the
  # mail: they are sent one at a time from the order, not swept up in a batch,
  # so the mail pile's count means nothing with them mixed in.
  ITEM_TYPE_TOGGLES = [
    { label: "Free Stickers", hidden_by_default: true, types: %w[ShopItem::FreeStickers] },
    { label: "Warehouse Item", hidden_by_default: true, types: %w[ShopItem::WarehouseItem] },
    { label: "HQ Mail", hidden_by_default: false, types: %w[ShopItem::HQMailItem] + ShopItem::LetterMail::BULK_BATCHED_TYPES },
    { label: "Streak Stickers", hidden_by_default: false, types: %w[ShopItem::StickyStreakSticker] }
  ].freeze

  # Sticky Streak stickers clear review on their own and ship outside the batch
  # sweep, and one 21-day run adds 21 of them per person, so counting them
  # alongside the orders a human actually works buries that work. They stay in
  # the queue below and keep their own toggle count; they just leave the
  # headline numbers alone.
  STATS_EXCLUDED_ITEM_TYPES = %w[ShopItem::StickyStreakSticker].freeze

  TOGGLEABLE_ITEM_TYPES = ITEM_TYPE_TOGGLES.flat_map { |toggle| toggle[:types] }.freeze

  DEFAULT_HIDDEN_ITEM_TYPES = ITEM_TYPE_TOGGLES.select { |toggle| toggle[:hidden_by_default] }
                                               .flat_map { |toggle| toggle[:types] }.freeze

  # Number of user groups shown per page when grouping by user.
  GROUPS_PER_PAGE = 25

  helper_method :preserved_filter_params, :grouped_by_user?, :item_type_toggles,
                :hidden_item_types, :grouping_toggle_params, :item_type_toggle_params,
                :item_type_toggle_hidden?, :assigned_to_me?, :assigned_to_me_toggle_params,
                :approvable_order?

  def approvable_order?(order)
    policy(order).approve? && order.user_id != current_user.id && order.approvable?
  end

  def preserved_filter_params
    params.permit(*PRESERVED_FILTER_KEYS)
  end

  # Fulfillment works order-by-order per person, so the queue groups by user
  # unless explicitly ungrouped. Every other view stays flat by default.
  def grouped_by_user?
    return params[:goob] != "false" if @view == "fulfillment"

    params[:goob] == "true"
  end

  def item_type_toggles
    ITEM_TYPE_TOGGLES
  end

  def item_type_toggle_hidden?(toggle)
    toggle[:types].all? { |type| hidden_item_types.include?(type) }
  end

  def hidden_item_types
    @hidden_item_types ||= if @view != "fulfillment"
      []
    else
      toggled = if params.key?(:hidden_types)
        Array(params[:hidden_types]) & TOGGLEABLE_ITEM_TYPES
      else
        DEFAULT_HIDDEN_ITEM_TYPES
      end

      # An explicit item-type filter beats the folded-away defaults, otherwise
      # filtering down to a hidden type would come back empty.
      (toggled | ALWAYS_HIDDEN_ITEM_TYPES) - [ params[:item_type] ]
    end
  end

  def grouping_toggle_params
    preserved_filter_params.merge(goob: !grouped_by_user?)
  end

  # Shortcut for the assignee filter below: narrowed to just the viewer's own
  # orders, or off. Mixed selections are made in the filter form itself.
  def assigned_to_me?
    Array(params[:assignee_ids]).map(&:to_s) == [ current_user.id.to_s ]
  end

  def assigned_to_me_toggle_params
    return preserved_filter_params.except(:assignee_ids) if assigned_to_me?

    preserved_filter_params.merge(assignee_ids: [ current_user.id.to_s ])
  end

  def item_type_toggle_params(toggle)
    next_hidden = if item_type_toggle_hidden?(toggle)
      hidden_item_types - toggle[:types]
    else
      hidden_item_types | toggle[:types]
    end

    # An empty array is dropped from the query string entirely, which would read
    # back as "no param given" and restore the defaults — send a blank entry so
    # "nothing hidden" survives the round trip.
    preserved_filter_params.merge(hidden_types: next_hidden.presence || [ "" ])
  end

  def index
    # Determine view mode
    @view = params[:view] || "shop_orders"
    @limit = params[:limit] || "10"

    authorize ShopOrder, :index?

    # Fulfillment team can only access fulfillment view - auto-redirect if needed
    # But fraud_dept members with fulfillment_person role should have full access
    if current_user.fulfillment_person? && !current_user.admin? && !current_user.fraud_dept?
      if @view != "fulfillment"
        redirect_to admin_shop_orders_path(view: "fulfillment") and return
      end
    end

    # Load fulfillment users for assignment dropdown (admins and fulfillment peeps, fulfillment view)
    if (current_user.admin? || current_user.fulfillment_person?) && @view == "fulfillment"
      @fulfillment_users = User.where("'fulfillment_person' = ANY(granted_roles)").order(:display_name)
    end

    # Base query
    orders = ShopOrder.includes(:shop_item, { user: :projects }, :accessory_orders, :assigned_to_user, mission_submission: :mission)

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
             .where.not(shop_item_id: ShopItem.where(type: STATS_EXCLUDED_ITEM_TYPES))

    # Folded-away item types only come off the list itself — the stats below and
    # the counts on the toggles stay whole so nothing vanishes silently.
    if hidden_item_types.any?
      orders = orders.where.not(shop_item_id: ShopItem.where(type: hidden_item_types))
    end

    if @view == "fulfillment"
      @awaiting_counts_by_type = apply_shared_filters(ShopOrder.joins(:shop_item))
                                   .where(aasm_state: "awaiting_periodical_fulfillment",
                                          shop_items: { type: TOGGLEABLE_ITEM_TYPES })
                                   .group("shop_items.type").count
    end

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
    # The fraud queue is worked oldest-first, and orders the automation would
    # clear on its own are its lowest priority, so those sink below everything
    # a person actually has to judge. Applied before the sort below so it stays
    # the primary key whichever ordering the reviewer picks.
    @auto_approvable_ids = auto_approvable_ids_in(orders)
    if @auto_approvable_ids.any?
      orders = orders.order(
        Arel.sql(ShopOrder.sanitize_sql_array([ "CASE WHEN shop_orders.id IN (?) THEN 1 ELSE 0 END", @auto_approvable_ids ]))
      )
    end

    sort_column, sort_direction = case params[:sort]
    when "id_asc" then [ :id, :asc ]
    when "id_desc" then [ :id, :desc ]
    when "created_at_desc" then [ :created_at, :desc ]
    when "shells_asc" then [ :frozen_item_price, :asc ]
    when "shells_desc" then [ :frozen_item_price, :desc ]
    else [ :created_at, :asc ]
    end
    orders = orders.order(sort_column => sort_direction)

    # Grouping. Paginate the *users* rather than the orders so every page holds
    # whole groups — grouping is the fulfillment default, so loading the entire
    # matching set at once isn't an option. Groups are ordered (and paginated)
    # by each user's most sort-relevant order — eg. sorting oldest-first
    # surfaces the user holding the oldest order first, even if that same user
    # also happens to hold the newest one.
    if grouped_by_user?
      aggregate = sort_direction == :asc ? :minimum : :maximum
      group_extremes = orders.unscope(:includes).reorder(nil).group(:user_id).public_send(aggregate, sort_column)
      user_ids = group_extremes.sort_by { |user_id, value| [ value, user_id ] }.map(&:first)
      user_ids.reverse! if sort_direction == :desc
      @pagy, page_user_ids = pagy(:offset, user_ids, limit: GROUPS_PER_PAGE)

      group_order = page_user_ids.each_with_index.to_h
      @grouped_orders = orders.where(user_id: page_user_ids).group_by(&:user).map do |user, user_orders|
        {
          user: user,
          orders: user_orders,
          total_items: user_orders.sum(&:quantity),
          total_shells: user_orders.sum { |o| o.total_cost || 0 }
        }
      end.sort_by { |g| group_order[g[:user].id] }
    else
      @pagy, @shop_orders = pagy(:offset, orders, limit: 50)
    end
  end

  def show
    if current_user.shop_manager? && !current_user.admin?
      authorize @order, :show?
    elsif current_user.fulfillment_person? && !current_user.admin? && !current_user.fraud_dept?
      authorize @order, :show?
    else
      authorize @order, :show?
    end

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
    @user_projects = @order.user.projects.includes(:hackatime_projects).order(created_at: :desc)

    if @order.shop_item.is_a?(ShopItem::LetterMail) && @order.awaiting_periodical_fulfillment?
      @theseus_sibling_orders = ShopOrder.joins(:shop_item)
                                         .where(shop_items: { type: @order.shop_item.type })
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
      authorize @order, :reveal_address?
    else
      authorize @order, :reveal_address?
    end

    if @order.can_view_address?(current_user)
      @decrypted_address = @order.decrypted_address_for(current_user)

      ::PaperTrail::Version.create!(
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
      authorize @order, :reveal_phone?
    else
      authorize @order, :reveal_phone?
    end

    if @order.can_view_address?(current_user)
      decrypted_address = @order.decrypted_address_for(current_user)
      phone_number = decrypted_address&.dig("phone_number")

      ::PaperTrail::Version.create!(
        item_type: "User",
        item_id: @order.user_id,
        event: "phone_revealed",
        whodunnit: current_user.id.to_s,
        object_changes: { order_id: @order.id, shop_item: @order.shop_item&.name }
      )

      phone_html = if phone_number.present?
        phone_safe = ERB::Util.html_escape(phone_number)
        <<~HTML.html_safe
          <div class="aorder__row">
            <span class="aorder__row-label">Phone</span>
            <span class="aorder__row-value">
              <span class="sensitive">#{phone_safe}</span>
              <button type="button" class="aorder__copy-btn" data-copy="#{phone_safe}" aria-label="Copy phone">📋</button>
            </span>
          </div>
          <div class="aorder__row" style="padding-top:var(--space-s);">
            <span class="aorder__row-label" style="color:var(--color-space-text-muted);font-size:var(--font-size-xs);">🔒 Phone access has been logged for security purposes.</span>
          </div>
          <script>
            document.querySelectorAll('.aorder__copy-btn').forEach(function(btn){
              if(btn._copyBound) return; btn._copyBound=true;
              btn.addEventListener('click',function(){
                navigator.clipboard.writeText(this.dataset.copy).then(function(){
                  btn.textContent='✓'; setTimeout(function(){btn.textContent='📋';},1500);
                });
              });
            });
          </script>
        HTML
      else
        <<~HTML.html_safe
          <div class="aorder__row">
            <span class="aorder__row-label">Phone</span>
            <span class="aorder__row-value" style="color:var(--color-space-text-muted);font-style:italic;">N/A</span>
          </div>
        HTML
      end

      render turbo_stream: turbo_stream.replace("phone-content", html: phone_html)
    else
      render plain: "Unauthorized", status: :forbidden
    end
  end

  def approve
    authorize @order, :approve?

    result = Admin::ShopOrderApprover.new(@order, actor: current_user, tracking_number: params[:tracking_number]).call

    if result.approved?
      redirect_to shop_orders_return_path, notice: result.message
    else
      redirect_to admin_shop_order_path(@order), alert: result.message
    end
  end

  def bulk_approve
    authorize ShopOrder, :approve?

    orders = ShopOrder.includes(:shop_item, :reviews).where(id: params[:order_ids])

    if orders.empty?
      redirect_back fallback_location: admin_shop_orders_path, alert: "No orders to approve." and return
    end

    approved, failed = orders.map { |order|
      Admin::ShopOrderApprover.new(order, actor: current_user).call
    }.partition(&:approved?)

    if approved.any?
      flash[:notice] = "Approved #{helpers.pluralize(approved.size, 'order')}: #{approved.map { |result| "##{result.order.id}" }.to_sentence}"
    end
    if failed.any?
      flash[:alert] = failed.map { |result| "##{result.order.id}: #{result.message}" }.join(" ")
    end

    redirect_back fallback_location: admin_shop_orders_path
  end

  def review_order
    authorize @order, :review_order?

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

        ::PaperTrail::Version.create!(
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
    authorize @order, :reject?

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
      ::PaperTrail::Version.create!(
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
        ::PaperTrail::Version.create!(
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
    authorize @order, :update?
    old_state = @order.aasm_state

    if @order.place_on_hold && @order.save
      ::PaperTrail::Version.create!(
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
    authorize @order, :update?
    old_state = @order.aasm_state

    if @order.take_off_hold && @order.save
      ::PaperTrail::Version.create!(
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
      authorize @order, :update?
    else
      authorize @order, :update?
    end

    if @order.shop_item.requires_verification_call? && !current_user.admin? && !@order.awaiting_periodical_fulfillment?
      redirect_to admin_shop_order_path(@order), alert: "Only admins can fulfill verification-call items" and return
    end

    old_state = @order.aasm_state

    if @order.mark_fulfilled(params[:external_ref].presence, params[:fulfillment_cost].presence, current_user.display_name) && @order.save
      ::PaperTrail::Version.create!(
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
      authorize @order, :update?
    else
      authorize @order, :update?
    end
    old_notes = @order.internal_notes

    if @order.update(internal_notes: params[:internal_notes])
      ::PaperTrail::Version.create!(
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
    authorize @order, :assign_user?
    old_assigned = @order.assigned_to_user_id

    new_assigned_id = params[:assigned_to_user_id].presence
    assigned_user = new_assigned_id ? User.find_by(id: new_assigned_id) : nil

    if @order.update(assigned_to_user_id: new_assigned_id)
      ::PaperTrail::Version.create!(
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
    authorize @order, :manage?
    old_state = @order.aasm_state

    unless @order.awaiting_verification_call?
      redirect_to shop_orders_return_path, alert: "Order cannot be approved because it is not currently awaiting a verification call." and return
    end

    if @order.queue_for_fulfillment && @order.save
      ::PaperTrail::Version.create!(
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
    authorize @order, :approve?

    unless @order.shop_card_grant.present?
      redirect_to admin_shop_order_path(@order), alert: "This order has no HCB grant to cancel"
      return
    end

    grant = @order.shop_card_grant
    begin
      HCBService.cancel_card_grant!(hashid: grant.hcb_grant_hashid)

      ::PaperTrail::Version.create!(
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

  # Only the fraud queue cares, and only a pending order can qualify, so the
  # question is asked about as few rows as possible. Reloaded with just the
  # associations the predicate reads rather than reusing the list's includes,
  # which drag in each buyer's projects for nothing.
  def auto_approvable_ids_in(scope)
    return [] unless @view == "shop_orders"

    candidates = ShopOrder
      .where(id: scope.unscope(:includes).reorder(nil).where(aasm_state: "pending").select(:id))
      .includes(:user, :shop_item, :selected_modifiers, accessory_orders: :shop_item)

    ShopOrder.auto_approvable_ids(candidates)
  end

  def set_order
    @order = ShopOrder.includes(mission_submission: :mission).find(params[:id])
  end

  def apply_shared_filters(scope)
    scope = scope.where(shop_item_id: params[:shop_item_id]) if params[:shop_item_id].present?
    scope = scope.where("created_at >= ?", params[:date_from]) if params[:date_from].present?
    scope = scope.where("created_at <= ?", params[:date_to]) if params[:date_to].present?

    if params[:item_type].present?
      scope = scope.joins(:shop_item).where(shop_items: { type: params[:item_type] })
    end

    if params[:min_tickets].present?
      scope = scope.where("shop_orders.frozen_item_price * shop_orders.quantity >= ?", params[:min_tickets])
    end
    if params[:max_tickets].present?
      scope = scope.where("shop_orders.frozen_item_price * shop_orders.quantity <= ?", params[:max_tickets])
    end

    # Presence/absence of a shipping tracking number.
    case params[:has_tracking]
    when "yes" then scope = scope.where.not(tracking_number: [ nil, "" ])
    when "no"  then scope = scope.where(tracking_number: [ nil, "" ])
    end

    # Standalone orders vs. modifier/accessory orders (which have a parent).
    case params[:order_type]
    when "standalone" then scope = scope.where(parent_order_id: nil)
    when "modifier"   then scope = scope.where.not(parent_order_id: nil)
    end

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
    authorize @order, :update?

    order_ids = (Array(params[:order_ids]).map(&:to_i) | [ @order.id ]).uniq

    @order.user.with_advisory_lock("theseus_send/#{@order.user_id}", timeout_seconds: 10) do
      orders_to_send = ShopOrder.joins(:shop_item)
                                .where(id: order_ids, shop_items: { type: @order.shop_item.type }, aasm_state: "awaiting_periodical_fulfillment")
                                .to_a

      stale_ids = order_ids - orders_to_send.map(&:id)
      if stale_ids.any?
        redirect_to admin_shop_order_path(@order), alert: "Order(s) #{stale_ids.join(', ')} no longer awaiting fulfillment. Please refresh and try again." and return
      end

      letter_id = TheseusService.create_letter(orders_to_send, queue: @order.shop_item.class::THESEUS_QUEUE)
      orders_to_send.each { |o| o.mark_fulfilled!(letter_id, nil, "#{current_user.display_name} - Letter Mail (Theseus)") }

      notice = "Sent to Theseus (letter #{letter_id})"
      notice += " — #{orders_to_send.size} orders coalesced" if orders_to_send.size > 1
      redirect_to admin_shop_order_path(@order), notice: notice
    rescue => e
      redirect_to admin_shop_order_path(@order), alert: "Failed to send to Theseus: #{e.message}"
    end
  end

  def refresh_verification
    authorize @order, :update?

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

    ::PaperTrail::Version.create!(
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
    authorize @order, :manage?

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

    ::PaperTrail::Version.create!(
      item: @order,
      event: "update",
      whodunnit: current_user.id.to_s,
      object_changes: { aasm_state: [ old_state, new_state ] }
    )

    redirect_to admin_shop_order_path(@order), notice: "State forced from #{old_state} to #{new_state}."
  end
end
