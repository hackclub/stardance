module Admin
  class ShopItemsController < Admin::ApplicationController
    before_action :set_shop_item, only: [ :show, :edit, :update, :destroy, :request_approval ]
    before_action :set_shop_item_types, only: [ :new, :edit ]
    before_action :set_fulfillment_users, only: [ :new, :edit, :create, :update ]

    def show
      authorize_shop_item_access!
      @pagy, @shop_orders = pagy(:offset, @shop_item.shop_orders.order(created_at: :desc), limit: 25)
    end

    def new
      authorize :admin, shop_manager? ? :manage_draft_shop_items? : :manage_shop?
      @shop_item = ShopItem.new
      if shop_manager?
        @shop_item.draft = true
        @shop_item.enabled = false
      else
        Shop::Regionalizable::REGION_CODES.each { |c| @shop_item.public_send("enabled_#{c.downcase}=", true) }
      end
    end

    def create
      authorize :admin, shop_manager? ? :manage_draft_shop_items? : :manage_shop?
      @shop_item = ShopItem.new(shop_manager? ? draft_shop_item_params : shop_item_params)

      if shop_manager?
        @shop_item.draft = true
        @shop_item.enabled = false
        @shop_item.created_by_user_id = current_user.id
      end

      if @shop_item.save
        redirect_to admin_shop_item_path(@shop_item), notice: shop_manager? ? "Draft item created." : "Shop item created successfully."
      else
        @shop_item_types = available_shop_item_types
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize_shop_item_access!(must_be_draft: true)
    end

    def update
      return unless authorize_shop_item_access!(must_be_draft: true)
      p = shop_manager? ? draft_shop_item_params : shop_item_params

      if @shop_item.update(p)
        if @shop_item.saved_change_to_ticket_cost?
          @shop_item.old_prices << @shop_item.ticket_cost_before_last_save
          @shop_item.save
        end

        if @shop_item.saved_change_to_blocked_countries?
          PaperTrail::Version.create!(
            item_type: "ShopItem",
            item_id: @shop_item.id,
            event: "blocked_countries_changed",
            whodunnit: current_user.id,
            object_changes: {
              blocked_countries: [
                @shop_item.blocked_countries_before_last_save,
                @shop_item.blocked_countries
              ]
            }.to_yaml
          )
        end

        redirect_to admin_shop_item_path(@shop_item), notice: "Shop item updated successfully."
      else
        @shop_item_types = available_shop_item_types
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize :admin, :manage_shop?
      @shop_item.destroy
      redirect_to admin_manage_shop_path, notice: "Shop item deleted successfully."
    end

    def preview_markdown
      authorize :admin, shop_manager? ? :manage_draft_shop_items? : :manage_shop?
      markdown = params[:markdown].to_s
      html = markdown.present? ? MarkdownRenderer.render(markdown) : ""
      render plain: html
    end

    def request_approval
      authorize :admin, :manage_draft_shop_items?
      unless @shop_item.draft? && @shop_item.created_by_user_id == current_user.id
        redirect_to admin_shop_item_path(@shop_item), alert: "You can only request approval for your own drafts." and return
      end

      PaperTrail::Version.create!(
        item_type: "ShopItem",
        item_id: @shop_item.id,
        event: "approval_requested",
        whodunnit: current_user.id,
        object_changes: { requested_by: current_user.display_name, requested_at: Time.current }.to_yaml
      )

      reviewer = User.find_by(id: 27)
      if reviewer&.slack_id.present?
        msg = "📋 *#{current_user.display_name}* requested approval for draft shop item \"#{@shop_item.name}\" — <#{Rails.application.routes.url_helpers.admin_shop_item_url(@shop_item, host: Rails.application.config.action_mailer.default_url_options&.dig(:host) || "stardance.hackclub.com")}|Review it>"
        SendSlackDmJob.perform_later(reviewer.slack_id, msg)
      end

      redirect_to admin_shop_item_path(@shop_item), notice: "Approval requested! An admin will review your draft."
    end

    private

    def shop_manager?
      current_user.shop_manager? && !current_user.admin?
    end

    def authorize_shop_item_access!(must_be_draft: false)
      if shop_manager?
        authorize :admin, :manage_draft_shop_items?
        if must_be_draft && (!@shop_item.draft? || @shop_item.created_by_user_id != current_user.id)
          redirect_to admin_manage_shop_path, alert: "You can only edit your own draft items."
          return false  # signal to caller
        end
      else
        authorize :admin, :manage_shop?
      end
      true
    end

    def set_shop_item
      @shop_item = ShopItem.find(params[:id])
    end

    def set_shop_item_types
      @shop_item_types = available_shop_item_types
    end

    def set_fulfillment_users
      @fulfillment_users = User.where("'fulfillment_person' = ANY(granted_roles)").order(:display_name)
    end

    def available_shop_item_types
      [
        "ShopItem::Accessory",
        "ShopItem::HCBGrant",
        "ShopItem::HCBPreauthGrant",
        "ShopItem::HQMailItem",
        "ShopItem::LetterMail",
        "ShopItem::ThirdPartyPhysical",
        "ShopItem::ThirdPartyDigital",
        "ShopItem::WarehouseItem",
        "ShopItem::SpecialFulfillmentItem",
        "ShopItem::HackClubberItem",
        "ShopItem::FreeStickers",
        "ShopItem::PileOfStickersItem",
        "ShopItem::SillyItemType"
      ]
    end

    def shop_item_params
      params.require(:shop_item).permit(
        :name,
        :type,
        :description,
        :long_description,
        :internal_description,
        :ticket_cost,
        :usd_cost,
        :enabled,
        :enabled_us,
        :enabled_ca,
        :enabled_eu,
        :enabled_uk,
        :enabled_in,
        :enabled_au,
        :enabled_xx,
        :usd_offset_us,
        :usd_offset_ca,
        :usd_offset_eu,
        :usd_offset_uk,
        :usd_offset_in,
        :usd_offset_au,
        :usd_offset_xx,
        :limited,
        :stock,
        :max_qty,
        :past_purchases,
        :one_per_person_ever,
        :show_in_carousel,
        :special,
        :sale_percentage,
        :payout_percentage,
        :user_id,
        :hacker_score,
        :unlock_on,
        :site_action,
        :hcb_category_lock,
        :hcb_keyword_lock,
        :hcb_merchant_lock,
        :hcb_preauthorization_instructions,
        :hcb_one_time_use,
        :agh_contents,
        :image,
        :buyable_by_self,
        :accessory_tag,
        :show_image_in_shop,
        :requires_ship,
        :required_ships_count,
        :required_ships_start_date,
        :required_ships_end_date,
        :default_assigned_user_id,
        :default_assigned_user_id_us,
        :default_assigned_user_id_eu,
        :default_assigned_user_id_uk,
        :default_assigned_user_id_ca,
        :default_assigned_user_id_au,
        :default_assigned_user_id_in,
        :default_assigned_user_id_xx,
        :unlisted,
        :enabled_until,
        :source_region,
        :requires_verification_call,
        requires_achievement: [],
        attached_shop_item_ids: [],
        blocked_countries: []
      )
    end

    def draft_shop_item_params
      params.require(:shop_item).permit(
        :name, :type, :description, :long_description, :internal_description,
        :ticket_cost, :usd_cost, :hacker_score, :sale_percentage, :image,
        :limited, :stock, :max_qty, :one_per_person_ever,
        :requires_ship, :required_ships_count, :required_ships_start_date, :required_ships_end_date,
        :source_region, :buyable_by_self, :accessory_tag, :show_image_in_shop,
        requires_achievement: [], blocked_countries: []
      )
    end
  end
end
