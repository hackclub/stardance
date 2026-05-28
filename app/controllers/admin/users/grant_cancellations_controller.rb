class Admin::Users::GrantCancellationsController < Admin::ApplicationController
  def create
    @user = User.find(params[:user_id])
    authorize @user, :cancel_grants?
    grants = @user.shop_card_grants.where.not(hcb_grant_hashid: nil)

    if grants.empty?
      redirect_to admin_user_path(@user), alert: "This user has no HCB grants to cancel"
      return
    end

    canceled_count = 0
    errors = []

    grants.find_each do |grant|
      begin
        HCBService.cancel_card_grant!(hashid: grant.hcb_grant_hashid)
        canceled_count += 1
      rescue => e
        errors << "Grant #{grant.hcb_grant_hashid}: #{e.message}"
      end
    end

    ::PaperTrail::Version.create!(
      item_type: "User",
      item_id: @user.id,
      event: "all_hcb_grants_canceled",
      whodunnit: current_user.id,
      object_changes: { canceled_count: canceled_count, canceled_by: current_user.display_name }.to_json
    )

    if errors.any?
      redirect_to admin_user_path(@user), alert: "Canceled #{canceled_count} grants, but #{errors.count} failed: #{errors.first}"
    else
      redirect_to admin_user_path(@user), notice: "Successfully canceled #{canceled_count} HCB grant(s)"
    end
  end
end
