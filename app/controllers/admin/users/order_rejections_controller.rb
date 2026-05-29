class Admin::Users::OrderRejectionsController < Admin::ApplicationController
  def create
    @user = User.find(params[:user_id])
    authorize @user, :reject_orders?
    reason = params[:reason].presence || "Rejected by fraud department"

    orders = @user.shop_orders.where(aasm_state: %w[pending awaiting_periodical_fulfillment])
    count = 0

    orders.each do |order|
      old_state = order.aasm_state
      if order.mark_rejected(reason) && order.save
        ::PaperTrail::Version.create!(
          item_type: "ShopOrder",
          item_id: order.id,
          event: "update",
          whodunnit: current_user.id,
          object_changes: {
            aasm_state: [ old_state, order.aasm_state ],
            rejection_reason: [ nil, reason ]
          }.to_json
        )
        count += 1
      end
    end

    flash[:notice] = "Rejected #{count} order(s) for #{@user.display_name}."
    redirect_to admin_user_path(@user)
  end
end
