class Admin::Users::IdentitiesController < Admin::ApplicationController
  before_action :set_user
  before_action :set_identity

  def destroy
    authorize @user, :unlink_identity?

    provider = @identity.provider
    uid = @identity.uid

    PaperTrail.request(whodunnit: current_user.id) do
      @identity.destroy!
    end

    ::PaperTrail::Version.create!(
      item_type: "User",
      item_id: @user.id,
      event: "identity_unlinked",
      whodunnit: current_user.id.to_s,
      object_changes: {
        provider: [ provider, nil ],
        uid: [ uid, nil ]
      }.to_json
    )

    flash[:notice] = "#{provider.titleize} identity unlinked from #{@user.display_name}."
    redirect_to admin_user_path(@user)
  end

  private

  def set_user
    @user = User.find(params[:user_id])
  end

  def set_identity
    @identity = @user.identities.find(params[:id])
  end
end
