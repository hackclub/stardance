class Admin::Users::OrderRejectionsController < Admin::ApplicationController
  def create
    @user = User.find(params[:user_id])
    authorize @user, :reject_orders?
    reason = params[:reason].presence || "Rejected by fraud department"
    internal_reason = params[:internal_rejection_reason].presence
    fraud_project_id = params[:fraud_related_project_id].presence
    joe_case_url = params[:joe_case_url].presence

    orders = @user.shop_orders.where(aasm_state: %w[pending awaiting_periodical_fulfillment])
    count = 0
    errors = []

    orders.each do |order|
      old_state = order.aasm_state
      order.internal_rejection_reason = internal_reason
      order.fraud_related_project_id = fraud_project_id
      order.joe_case_url = joe_case_url

      if order.mark_rejected(reason) && order.save
        ::PaperTrail::Version.create!(
          item_type: "ShopOrder",
          item_id: order.id,
          event: "update",
          whodunnit: current_user.id,
          object_changes: {
            aasm_state: [ old_state, order.aasm_state ],
            rejection_reason: [ nil, reason ],
            internal_rejection_reason: [ nil, internal_reason ],
            fraud_related_project_id: [ nil, fraud_project_id ],
            joe_case_url: [ nil, joe_case_url ]
          }.compact_blank
        )
        count += 1
      else
        errors.concat(order.errors.full_messages)
      end
    end

    if errors.any?
      flash[:alert] = "Rejected #{count} order(s), but #{orders.size - count} failed: #{errors.uniq.to_sentence}."
    else
      flash[:notice] = "Rejected #{count} order(s) for #{@user.display_name}."
    end
    redirect_to admin_user_path(@user)
  end
end
