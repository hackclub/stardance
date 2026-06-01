class Onboarding::WizardController < ApplicationController
  include OnboardingResumable

  layout "onboarding"

  before_action :require_onboarding_guest!,  only: %i[welcome birthday submit_birthday
                                                      experience submit_experience experience_result
                                                      interests submit_interests interests_result
                                                      referral submit_referral
                                                      name submit_name]
  before_action :require_teen_attestation!,  only: %i[experience submit_experience experience_result
                                                      interests submit_interests interests_result
                                                      referral submit_referral
                                                      name submit_name]

  def start
    # Already completed onboarding — nothing to do.
    if current_user&.onboarded_at.present?
      redirect_to home_path and return
    end

    email = params[:email].to_s.strip
    if email.blank? || !email.match?(URI::MailTo::EMAIL_REGEXP)
      redirect_to root_path, alert: "Please enter a valid email address." and return
    end

    normalized = email.downcase
    existing = User.find_by(email: normalized)

    if existing&.hca_linked?
      if existing.age_attestation_ineligible?
        redirect_to onboarding_age_gate_path and return
      end

      if existing.onboarded_at.nil?
        session[:user_id] = existing.id
        redirect_to onboarding_resume_path(existing) and return
      end

      # OmniAuth 2.x with omniauth-rails_csrf_protection blocks GET, so we
      # render an auto-submitting POST form instead of redirecting.
      @login_hint = normalized
      return render :redirecting_to_hca
    end

    if existing
      session[:user_id] = existing.id

      if onboarding_in_progress?(existing)
        if onboarding_fresh?(existing)
          redirect_to onboarding_resume_path(existing) and return
        else
          restart_onboarding!(existing)
          redirect_to onboarding_welcome_path and return
        end
      end

      redirect_to home_path and return
    end

    guest_email_owner = User.find_by(guest_email: normalized)
    if guest_email_owner
      session[:guest_email_claim] = normalized
      redirect_to onboarding_guest_email_path and return
    end

    user = create_guest!(normalized)
    session[:user_id] = user.id
    UserMailer.onboarding_start(user).deliver_later
    track_event "onboarding_started", { user_id: user.id }

    if HCAService.email_known?(normalized)
      @login_hint = normalized
      return render :redirecting_to_hca
    end

    redirect_to onboarding_welcome_path
  end

  def welcome; end

  def birthday
    if current_user.age_attestation_ineligible?
      reset_session
      redirect_to onboarding_age_gate_path
    elsif current_user.age_attestation.present?
      redirect_to params[:back] ? onboarding_welcome_path : onboarding_resume_path(current_user)
    end
  end

  def submit_birthday
    if current_user.age_attestation_ineligible?
      reset_session
      redirect_to onboarding_age_gate_path and return
    end

    if current_user.age_attestation.present?
      redirect_to onboarding_resume_path(current_user) and return
    end

    case params[:attestation]
    when "teen_13_18"
      current_user.update!(age_attestation: "teen_13_18")
      track_event "onboarding_age_attested", { attestation: "teen_13_18" }
      redirect_to onboarding_experience_path
    when "ineligible"
      current_user.destroy
      reset_session
      redirect_to onboarding_age_gate_path
    else
      redirect_to onboarding_birthday_path, alert: "Please pick one."
    end
  end

  def age_gate; end

  def experience; end

  def submit_experience
    level = params[:level].to_s
    unless User.experience_levels.key?(level)
      redirect_to onboarding_experience_path, alert: "Please pick one." and return
    end

    current_user.update!(experience_level: level)
    track_event "onboarding_experience_selected", { level: level }
    redirect_to onboarding_experience_result_path
  end

  def experience_result
    @level = current_user.experience_level
    @peer_count = User.where(experience_level: @level)
                      .where.not(id: current_user.id)
                      .count
  end

  def interests
    @selected = current_user.interests || []
  end

  def submit_interests
    submitted = Array(params[:interests])
    if submitted.include?(User::INTERESTS_UNKNOWN)
      current_user.update!(interests: [ User::INTERESTS_UNKNOWN ])
      track_event "onboarding_interests_selected", { interests: [ User::INTERESTS_UNKNOWN ] }
      redirect_to onboarding_interests_result_path and return
    end

    selected = submitted & User::ALLOWED_INTERESTS
    if selected.empty?
      redirect_to onboarding_interests_path, alert: "Pick at least one." and return
    end

    current_user.update!(interests: selected)
    track_event "onboarding_interests_selected", { interests: selected }
    redirect_to onboarding_interests_result_path
  end

  def interests_result
    @interests = current_user.interests || []
    if @interests.present? && @interests != [ User::INTERESTS_UNKNOWN ]
      @peer_count = User.where("interests && ARRAY[?]::varchar[]", @interests)
                        .where.not(id: current_user.id)
                        .count
      if current_user.experience_level == "none"
        @beginner_peer_count = User.where("interests && ARRAY[?]::varchar[]", @interests)
                                   .where(experience_level: "none")
                                   .where.not(id: current_user.id)
                                   .count
      end
      @featured_projects = Onboarding::FeaturedProjects.for_interests(@interests)
    end
  end

  def referral
    rsvp = matching_rsvp

    if current_user.ref.blank? && rsvp&.ref.present?
      current_user.update_column(:ref, rsvp.ref)
    end

    redirect_to onboarding_name_path and return if current_user.user_ref.present?

    @suggested_user_ref = rsvp&.user_ref.presence
  end

  def submit_referral
    value = params[:user_ref].to_s.strip
    value = params[:user_ref_other].to_s.strip.first(100) if value == "Other"
    current_user.update(user_ref: value.presence)
    track_event "onboarding_referral_submitted", { user_ref: value.presence }
    redirect_to onboarding_name_path
  end

  def name
    @display_name_default = default_name_from_email
  end

  MAX_DISPLAY_NAME_LENGTH = User::MAX_DISPLAY_NAME_LENGTH

  def submit_name
    display_name = params[:display_name].to_s.strip
    if display_name.blank?
      redirect_to onboarding_name_path, alert: "Please enter a name." and return
    end
    if display_name.length > MAX_DISPLAY_NAME_LENGTH
      redirect_to onboarding_name_path, alert: "That's a really long name — please keep it under #{MAX_DISPLAY_NAME_LENGTH} characters." and return
    end

    if current_user.update(display_name: display_name, onboarded_at: Time.current)
      track_event "onboarding_completed", { display_name: display_name }
      redirect_to home_path(welcome: 1)
    else
      alert = if current_user.errors[:display_name].any? { |m| m =~ /taken/i }
                "That name is already taken — try another."
      else
                current_user.errors.full_messages.to_sentence.presence || "Couldn't save that name — try another."
      end
      redirect_to onboarding_name_path, alert: alert
    end
  end

  def guest_email
    @claimed_email = session[:guest_email_claim]
    unless @claimed_email
      redirect_to root_path and return
    end

    owner = User.find_by(guest_email: @claimed_email)
    unless owner
      session.delete(:guest_email_claim)
      redirect_to root_path and return
    end

    @censored_hca_email = censor_email(owner.email)
  end

  def guest_email_yes
    claimed_email = session.delete(:guest_email_claim)
    owner = User.find_by(guest_email: claimed_email)

    unless owner
      redirect_to root_path, alert: "Something went wrong. Please try again." and return
    end

    @login_hint = owner.email
    @nudge_email = owner.email
    render :redirecting_to_hca
  end

  def guest_email_no
    claimed_email = session.delete(:guest_email_claim)
    owner = User.find_by(guest_email: claimed_email)
    owner&.update!(guest_email: nil)

    user = create_guest!(claimed_email)
    session[:user_id] = user.id
    redirect_to onboarding_welcome_path
  end

  private

  def signup_referral_code
    code = cookies[:referral_code].presence
    code if code && code.length <= 64
  end

  def matching_rsvp
    return @matching_rsvp if defined?(@matching_rsvp)

    email = current_user.email.to_s.downcase
    @matching_rsvp = email.present? ? Rsvp.find_by(email: email) : nil
  end

  def censor_email(email)
    local, domain = email.split("@", 2)
    return email if local.length <= 2

    "#{local[0]}#{"*" * (local.length - 2)}#{local[-1]}@#{domain}"
  end

  def create_guest!(email)
    ref = signup_referral_code
    5.times do
      user = User.new(
        email: email,
        display_name: User.placeholder_display_name_from_email(email),
        ref: ref,
        ip_address: client_ip_address,
        user_agent: request.user_agent
      )
      return user if user.save
      # Email collision means the user already exists — hand back the existing
      # record. For any other error (most likely a display_name collision in
      # the small Kerbal pool), retry with a fresh random name.
      return User.find_by(email: email) || raise(ActiveRecord::RecordInvalid.new(user)) if user.errors[:email].any?
    end
    raise ActiveRecord::RecordInvalid.new(User.new(email: email))
  rescue ActiveRecord::RecordNotUnique
    # Race against another request creating the same email — fall back to lookup.
    User.find_by(email: email) or raise
  end

  def require_onboarding_guest!
    return if current_user.present? && current_user.onboarded_at.nil?
    redirect_to root_path, alert: "Please start signup from the homepage."
  end

  def require_teen_attestation!
    return if current_user&.age_attestation_teen_13_18?
    redirect_to onboarding_birthday_path
  end

  def default_name_from_email
    local = current_user.email.to_s.split("@").first.to_s
    return nil if local.blank?

    local.gsub(/[^a-zA-Z0-9_-]/, "_").first(MAX_DISPLAY_NAME_LENGTH).presence
  end
end
