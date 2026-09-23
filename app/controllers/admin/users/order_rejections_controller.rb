class Admin::Users::OrderRejectionsController < Admin::ApplicationController
  def create
    @user = User.find(params[:user_id])
    authorize @user, :reject_orders?
    orders = @user.shop_orders.where(aasm_state: %w[pending awaiting_periodical_fulfillment])
    rejected, undecided = orders.map { |order|
      Admin::ShopOrderRejector.new(
        order,
        actor: current_user,
        reason: params[:reason].presence || "Rejected by fraud department",
        internal_reason: params[:internal_rejection_reason],
        fraud_project_id: params[:fraud_related_project_id],
        joe_case_url: params[:joe_case_url]
      ).call
    }.partition(&:rejected?)

    # A high-value order takes two reviewers, so this pass can only record the
    # rejection for the ones nobody else has rejected yet.
    voted, failed = undecided.partition(&:review)

    if failed.any?
      flash[:alert] = "Rejected #{rejected.size} order(s), but #{failed.size} failed: #{failed.map(&:message).uniq.to_sentence}."
    else
      flash[:notice] = "Rejected #{rejected.size} order(s) for #{@user.display_name}."
    end

    if voted.any?
      flash[:notice] = [ flash[:notice],
                         "#{voted.size} high-value order(s) now wait on a second reviewer's rejection." ].compact.join(" ")
    end

    redirect_to admin_user_path(@user)
  end
end
