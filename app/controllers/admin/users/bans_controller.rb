class Admin::Users::BansController < Admin::ApplicationController
  before_action :set_user

  def create
    authorize @user, :ban?

    reason = params[:reason].presence

    PaperTrail.request(whodunnit: current_user.id) do
      @user.ban!(reason: reason)
    end

    ::PaperTrail::Version.create!(
      item_type: "User",
      item_id: @user.id,
      event: "banned",
      whodunnit: current_user.id.to_s,
      object_changes: {
        banned: [ false, true ],
        banned_reason: [ nil, reason ]
      }.to_json
    )

    flash[:notice] = "#{@user.display_name} has been banned."
    redirect_to admin_user_path(@user)
  end

  def destroy
    authorize @user, :ban?

    old_reason = @user.banned_reason

    PaperTrail.request(whodunnit: current_user.id) do
      @user.unban!
    end

    ::PaperTrail::Version.create!(
      item_type: "User",
      item_id: @user.id,
      event: "unbanned",
      whodunnit: current_user.id.to_s,
      object_changes: {
        banned: [ true, false ],
        banned_reason: [ old_reason, nil ]
      }.to_json
    )

    flash[:notice] = "#{@user.display_name} has been unbanned."
    redirect_to admin_user_path(@user)
  end

  private

  def set_user
    @user = User.find(params[:user_id])
  end
end
