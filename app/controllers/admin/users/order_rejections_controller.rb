class Admin::Users::OrderRejectionsController < Admin::ApplicationController
  def create
    @user = User.find(params[:user_id])
    authorize @user, :reject_orders?
    orders = @user.shop_orders.where(aasm_state: %w[pending awaiting_periodical_fulfillment])
    rejected, failed = orders.map { |order|
      Admin::ShopOrderRejector.new(
        order,
        actor: current_user,
        reason: params[:reason].presence || "Rejected by fraud department",
        internal_reason: params[:internal_rejection_reason],
        fraud_project_id: params[:fraud_related_project_id],
        joe_case_url: params[:joe_case_url]
      ).call
    }.partition(&:rejected?)

    if failed.any?
      flash[:alert] = "Rejected #{rejected.size} order(s), but #{failed.size} failed: #{failed.map(&:message).uniq.to_sentence}."
    else
      flash[:notice] = "Rejected #{rejected.size} order(s) for #{@user.display_name}."
    end
    redirect_to admin_user_path(@user)
  end
end
