class Admin::UsersController < Admin::ApplicationController
    skip_before_action :prevent_admin_access_while_impersonating, only: [ :stop_impersonating ]

    def index
      @query = params[:query]

      users = User.all
      if @query.present?
        q = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
        users = users.where("email ILIKE ? OR display_name ILIKE ? OR slack_id ILIKE ?", q, q, q)
      end

      @pagy, @users = pagy(:offset, users.order(:id))
    end

    def impersonate
      @user = User.find(params[:id]) # user to be impersonated
      authorize @user

      admin_user = current_user
      # simple swap
      session[:impersonator_user_id] = admin_user.id
      session[:user_id] = @user.id
      pundit_reset!

      PaperTrail::Version.create!(
        item_type: "User",
        item_id: @user.id,
        event: "impersonation_started",
        whodunnit: admin_user.id.to_s,
        object_changes: {
          impersonated_by: admin_user.id,
          impersonated_by_name: admin_user.display_name
        }.to_json
      )

      flash[:notice] = "Now impersonating #{@user.display_name}. You can stop impersonation from the banner at the top."
      redirect_to root_path
    end

    def stop_impersonating
      if real_user && current_user # current_user is impersonated user
          PaperTrail::Version.create!(
            item_type: "User",
            item_id: current_user.id,
            event: "impersonation_stopped",
            whodunnit: real_user.id.to_s,
            object_changes: {
              stopped_by: real_user.id,
              stopped_by_name: real_user.display_name
            }.to_json
          )
      end

        session[:user_id] = real_user.id
        session.delete(:impersonator_user_id)
        pundit_reset!
        flash[:notice] = "Stopped impersonating #{current_user&.display_name}."

      redirect_to admin_users_path
    end

    def show
      @user = User.includes(:identities).find(params[:id])

      @all_projects = @user.projects.with_deleted.order(deleted_at: :desc)
    end

    def user_perms
      authorize :admin, :manage_users?
      @users = User.where("array_length(granted_roles, 1) > 0").order(:id)
    end

    def promote_role
      authorize :admin, :manage_user_roles?

      @user = User.find(params[:id])
      role_name = params[:role_name]

      if role_name == "admin" && !current_user.super_admin?
        flash[:alert] = "Only super admins can promote to admin."
        return redirect_to admin_user_path(@user)
      end

      if role_name == "super_admin" && !current_user.super_admin?
        flash[:alert] = "#{current_user.display_name} is not in the sudoers file."
        return redirect_to admin_user_path(@user)
      end

      @user.grant_role!(role_name)

      # Create explicit audit entry on User
      PaperTrail::Version.create!(
        item_type: "User",
        item_id: @user.id,
        event: "role_promoted",
        whodunnit: current_user.id.to_s,
        object_changes: { role: role_name }.to_json
      )

      flash[:notice] = "User promoted to #{role_name.titleize}."

      redirect_to admin_user_path(@user)
    end

  def demote_role
    authorize :admin, :manage_user_roles?

    @user = User.find(params[:id])
    role_name = params[:role_name]

    if role_name == "super_admin" && !current_user.super_admin?
      flash[:alert] = "Only super admins can demote super admin."
      return redirect_to admin_user_path(@user)
    end

    if @user.has_role?(role_name)
      @user.remove_role!(role_name)

      # Create explicit audit entry on User
      PaperTrail::Version.create!(
        item_type: "User",
        item_id: @user.id,
        event: "role_demoted",
        whodunnit: current_user.id.to_s,
        object_changes: { role: role_name }.to_json
      )

      flash[:notice] = "User demoted from #{role_name.titleize}."
    else
      flash[:alert] = "Unable to demote user from #{role_name.titleize}."
    end

    redirect_to admin_user_path(@user)
  end

  def toggle_flipper
    authorize :admin, :access_flipper?

    @user = User.find(params[:id])
    feature = params[:feature].to_sym

    if Flipper.enabled?(feature, @user)
      Flipper.disable(feature, @user)
      PaperTrail::Version.create!(
        item_type: "User",
        item_id: @user.id,
        event: "flipper_disable",
        whodunnit: current_user.id,
        object_changes: { feature: [ feature.to_s, nil ], status: [ "enabled", "disabled" ] }.to_json
      )
      flash[:notice] = "Disabled #{feature} for #{@user.display_name}."
    else
      Flipper.enable(feature, @user)
      PaperTrail::Version.create!(
        item_type: "User",
        item_id: @user.id,
        event: "flipper_enable",
        whodunnit: current_user.id,
        object_changes: { feature: [ nil, feature.to_s ], status: [ "disabled", "enabled" ] }.to_json
      )
      flash[:notice] = "Enabled #{feature} for #{@user.display_name}."
    end

    redirect_to admin_user_path(@user)
  end

  def sync_hackatime
    authorize :admin, :manage_users?
    @user = User.find(params[:id])

    if @user.hackatime_identity
      @user.try_sync_hackatime_data!(force: true)
      flash[:notice] = "Hackatime data synced for #{@user.display_name}."
    else
      flash[:alert] = "User does not have a Hackatime identity."
    end

    redirect_to admin_user_path(@user)
  end

  def mass_reject_orders
    authorize :admin, :access_shop_orders?
    @user = User.find(params[:id])
    reason = params[:reason].presence || "Rejected by fraud department"

    orders = @user.shop_orders.where(aasm_state: %w[pending awaiting_periodical_fulfillment])
    count = 0

    orders.each do |order|
      old_state = order.aasm_state
      if order.mark_rejected(reason) && order.save
        PaperTrail::Version.create!(
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

  def adjust_balance
    authorize :admin, :manage_users?
    @user = User.find(params[:id])

    if cannot_adjust_balance_for?(@user)
      flash[:alert] = "You cannot adjust the balance of another #{protected_role_name(@user)}."
      return redirect_to admin_user_path(@user)
    end

    amount = params[:amount].to_i
    reason = params[:reason].presence

    if fraud_dept_cookie_limit_exceeded?(amount)
      flash[:alert] = "Fraud department members can only grant up to 1 cookie without the grant_cookies permission."
      return redirect_to admin_user_path(@user)
    end

    if amount.zero?
      flash[:alert] = "Amount cannot be zero."
      return redirect_to admin_user_path(@user)
    end

    if reason.blank?
      flash[:alert] = "Reason is required."
      return redirect_to admin_user_path(@user)
    end

    @user.ledger_entries.create!(
      amount: amount,
      reason: reason,
      created_by: "#{current_user.display_name} (#{current_user.id})",
      ledgerable: @user
    )

    flash[:notice] = "Balance adjusted by #{amount} for #{@user.display_name}."
    redirect_to admin_user_path(@user)
  end

  def set_ysws_eligible_override
    authorize :admin, :manage_users?
    @user = User.find(params[:id])

    raw_override = params[:manual_ysws_override]
    new_override = raw_override=="true" ? true : nil
    old_override = @user.manual_ysws_override
    @user.manual_ysws_override = new_override

    if @user.save
      PaperTrail::Version.create!(
        item_type: "User",
        item_id: @user.id,
        event: "manual_ysws_override_set",
        whodunnit: current_user.id.to_s,
        object_changes: { manual_ysws_override: [ old_override, new_override ] }.to_json
      )

      if @user.eligible_for_shop?
        Shop::ProcessVerifiedOrdersJob.perform_later(@user.id)
      end

      flash[:notice] = "YSWS eligibility overridden, now #{@user.ysws_eligible? ? 'eligible' : 'ineligible'}."
    else
      flash[:alert] = "Failed to update override"
    end
    redirect_to admin_user_path(@user)
  end

  def ban
    authorize :admin, :ban_users?
    @user = User.find(params[:id])
    reason = params[:reason].presence

    PaperTrail.request(whodunnit: current_user.id) do
      @user.ban!(reason: reason)
    end

    PaperTrail::Version.create!(
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

  def unban
    authorize :admin, :ban_users?
    @user = User.find(params[:id])
    old_reason = @user.banned_reason

    PaperTrail.request(whodunnit: current_user.id) do
      @user.unban!
    end

    PaperTrail::Version.create!(
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

  def set_vote_balance
    authorize :admin, :manage_users?
    u = User.find(params[:id])
    old = u.vote_balance
    val = params[:vote_balance].to_i
    u.update!(vote_balance: val)
    PaperTrail::Version.create!(
      item_type: "User", item_id: u.id, event: "vote_balance_set",
      whodunnit: current_user.id.to_s,
      object_changes: { vote_balance: [ old, val ] }.to_json
    )
    redirect_back(fallback_location: admin_user_path(u), notice: "Vote balance set to #{val} for #{u.display_name}.")
  end

  def toggle_voting_lock
    authorize :admin, :ban_users?
    @user = User.find(params[:id])
    @user.toggle!(:voting_locked)

    PaperTrail::Version.create!(
      item_type: "User",
      item_id: @user.id,
      event: "voting_lock_toggled",
      whodunnit: current_user.id.to_s,
      object_changes: { voting_locked: [ !@user.voting_locked, @user.voting_locked ] }.to_json
    )

    redirect_back(fallback_location: admin_user_path(@user), notice: "Voting lock has been #{@user.voting_locked ? 'enabled' : 'disabled'} for #{@user.display_name}.")
  end

  def refresh_verification
    authorize :admin, :manage_users?
    @user = User.find(params[:id])

    identity = @user.identities.find_by(provider: "hack_club")

    unless identity&.access_token.present?
      flash[:alert] = "User has no Hack Club identity token."
      return redirect_to admin_user_path(@user)
    end

    payload = HCAService.identity(identity.access_token)
    if payload.blank?
      flash[:alert] = "Could not fetch verification status from HCA."
      return redirect_to admin_user_path(@user)
    end

    status = payload["verification_status"].to_s
    ysws_eligible = payload["ysws_eligible"] == true

    old_status = @user.verification_status
    old_ysws = @user.ysws_eligible
    @user.verification_status = status if User.verification_statuses.key?(status)
    @user.ysws_eligible = ysws_eligible
    @user.save!

    PaperTrail::Version.create!(
      item_type: "User",
      item_id: @user.id,
      event: "verification_refreshed",
      whodunnit: current_user.id.to_s,
      object_changes: {
        verification_status: [ old_status, @user.verification_status ],
        ysws_eligible: [ old_ysws, @user.ysws_eligible ]
      }.to_json
    )

    if @user.eligible_for_shop?
      Shop::ProcessVerifiedOrdersJob.perform_later(@user.id)
      flash[:notice] = "User is now verified (#{@user.verification_status}). Processing awaiting orders..."
    elsif @user.should_reject_orders?
      @user.reject_awaiting_verification_orders!
      flash[:notice] = "User verification failed (#{@user.verification_status}). Awaiting orders rejected."
    else
      flash[:notice] = "Verification status updated to: #{@user.verification_status}"
    end

    redirect_to admin_user_path(@user)
  rescue StandardError => e
    Rails.logger.error "Failed to refresh verification status for user #{@user.id}: #{e.message}"
    flash[:alert] = "Error refreshing verification: #{e.message}"
    redirect_to admin_user_path(@user)
  end

  def votes
    authorize :admin, :manage_users?
    @user = User.find(params[:id])

    @pagy, @votes = pagy(
      @user.votes.includes(:project).order(created_at: :desc)
    )
  end

  def update
    authorize :admin, :manage_users?
    @user = User.find(params[:id])

    old_regions = @user.regions.dup

    # Filter out empty strings from regions array
    if params[:user][:regions].present?
      params[:user][:regions] = params[:user][:regions].reject(&:blank?)
    end

    if @user.update(user_params)
      if old_regions != @user.regions
        PaperTrail::Version.create!(
          item_type: "User",
          item_id: @user.id,
          event: "regions_updated",
          whodunnit: current_user.id.to_s,
          object_changes: { regions: [ old_regions, @user.regions ] }.to_json
        )
      end
      flash[:notice] = "User updated successfully."
    else
      flash[:alert] = "Failed to update user."
    end

    redirect_to admin_user_path(@user)
  end

  def cancel_all_hcb_grants
    authorize :admin, :manage_users?
    @user = User.find(params[:id])

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

    PaperTrail::Version.create!(
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

  private

  def user_params
    params.require(:user).permit(:internal_notes, regions: [])
  end

  def cannot_adjust_balance_for?(target_user)
    return false if current_user.has_role?(:super_admin) || current_user.has_role?(:admin)

    # Non-admins cannot adjust their own balance
    return true if target_user == current_user

    # Fraud dept cannot modify admin balances at all
    if current_user.has_role?(:fraud_dept)
      return true if target_user.has_role?(:admin) || target_user.has_role?(:super_admin)
    end

    protected_roles = [ :admin, :super_admin, :fraud_dept ]
    shared_protected_roles = current_user.roles & protected_roles & target_user.roles
    shared_protected_roles.any?
  end

  def fraud_dept_cookie_limit_exceeded?(amount)
    return false unless current_user.has_role?(:fraud_dept)
    return false if current_user.has_role?(:admin) || current_user.has_role?(:super_admin)
    return false if Flipper.enabled?(:grant_cookies, current_user)

    amount > 1
  end

  def protected_role_name(target_user)
    if target_user.has_role?(:super_admin) || target_user.has_role?(:admin)
      "admin"
    elsif target_user.has_role?(:fraud_dept)
      "fraud department member"
    else
      "user"
    end
  end
end
