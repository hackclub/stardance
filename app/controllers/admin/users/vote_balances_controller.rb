class Admin::Users::VoteBalancesController < Admin::ApplicationController
  def update
    @user = User.find(params[:user_id])
    authorize @user, :set_vote_balance?
    old = @user.vote_balance
    val = params[:vote_balance].to_i
    @user.update!(vote_balance: val)

    ::PaperTrail::Version.create!(
      item_type: "User", item_id: @user.id, event: "vote_balance_set",
      whodunnit: current_user.id.to_s,
      object_changes: { vote_balance: [ old, val ] }.to_json
    )

    redirect_back(fallback_location: admin_user_path(@user), notice: "Vote balance set to #{val} for #{@user.display_name}.")
  end
end
