class SessionsController < ApplicationController
  include OnboardingResumable

  def create
    result = Sessions::HCALoginService.new(
      auth: request.env["omniauth.auth"],
      current_user: current_user,
      referral_code: cookies[:referral_code],
      ip_address: client_ip_address,
      user_agent: request.user_agent
    ).call

    unless result.ok?
      if result.status == :age_violation
        reset_session
        return redirect_to(onboarding_age_gate_path, alert: result.alert)
      end
      return redirect_to(root_path, alert: result.alert)
    end

    reset_session if result.guest_collision
    sign_in_user(result.user, auth_level: "hca")

    return_to = safe_return_to(session.delete(:return_to))

    if result.is_new_user
      UserMailer.onboarding_start(result.user).deliver_later
    end

    destination = if result.user.onboarded_at.nil? && result.user.age_blocked?
      onboarding_age_gate_path
    elsif result.user.onboarded_at.nil? && result.is_new_user
      onboarding_welcome_path
    elsif result.user.onboarded_at.nil?
      onboarding_resume_path(result.user)
    elsif return_to
      return_to
    elsif result.user.setup_complete?
      profile_projects_path(result.user.display_name)
    else
      home_path
    end

    track_event "signed_up", { user_id: result.user.id } if result.is_new_user
    track_event "hca_linked", { user_id: result.user.id } if result.is_new_user || result.guest_collision
    redirect_to destination, notice: raffle_referral_notice(result.user) || "Signed in with Hack Club"
  end

  def destroy
    reset_session
    redirect_to root_path
  end

  def dismiss_raffle_banner
    session.delete(:show_raffle_referral_banner)
    redirect_back fallback_location: root_path, allow_other_host: false
  end

  def failure
    redirect_to root_path, alert: "Authentication failed"
  end

  def dev_login
    return head :not_found unless Rails.env.development? || Rails.env.test?

    user = if params[:id].present?
      User.find_by(id: params[:id])
    else
      User.find_by(id: ENV["DEV_ADMIN_USER_ID"]) || User.order(:id).first
    end

    unless user
      return redirect_to(root_path, alert: "No users found for dev login. Create a user first.")
    end

    ensure_dev_hca_identity(user) unless params[:id].present?

    sign_in_user(user, auth_level: user.hca_linked? ? "hca" : "guest")
    session[:show_raffle_referral_banner] = params[:raffle_referrer] if params[:raffle_referrer].present?
    if Rails.env.test?
      head :ok
    else
      redirect_to "/projects", notice: "Dev logged in as #{user.display_name}"
    end
  end

  private

  def ensure_dev_hca_identity(user)
    return if user.hca_linked?

    user.create_hack_club_identity!(provider: "hack_club", uid: "dev-#{user.id}", access_token: "dev-access-token")
  end

  def raffle_referral_notice(user)
    referral = Raffle::Referral.includes(:participant).find_by(referred_user_id: user.id, status: :verified)
    return unless referral

    participant = referral.participant
    session[:show_raffle_referral_banner] = participant.display_name
    session[:raffle_referrer_is_adult] = participant.age_group_adult?
    nil
  rescue StandardError
    nil
  end

  def safe_return_to(path)
    return nil if path.blank?

    uri = URI.parse(path)
    return nil if uri.host.present? || uri.scheme.present?
    return nil unless path.start_with?("/")
    return nil if path.start_with?("//", "/\\")
    path
  rescue URI::InvalidURIError
    nil
  end
end
