class LandingController < ApplicationController
  skip_before_action :remember_page,
                     :initialize_cache_counters,
                     :track_active_user,
                     :show_pending_achievement_notifications!,
                     :apply_dev_override_ref,
                     raise: false

  def index
    @hide_sidebar = true
    @user_ref_token = flash[:user_ref_token]
    @prefill_email = params[:e]
    prepare_landing_page_state

    if current_user
      redirect_to home_path
    else
      respond_to do |format|
        format.html { render :index }
      end
    end
  end

  def edu
    @hide_sidebar = true
    prepare_landing_page_state
  end

  def signup_count
    count = cached_signup_count
    render json: { count: count }
  end

  def rsvp_count
    count = cached_rsvp_count
    render json: { count: count }
  end

  private

  def prepare_landing_page_state
    @new_onboarding = Flipper.enabled?(:new_onboarding)
    if @new_onboarding
      @signup_count = cached_signup_count
    else
      @rsvp_count = cached_rsvp_count
    end
  end

  def cached_rsvp_count
    Rails.cache.fetch("landing/rsvp_count", expires_in: 30.seconds) { Rsvp.count }
  end

  def cached_signup_count
    Rails.cache.fetch("landing/signup_count", raw: true, expires_in: 30.seconds) {
      User.deduplicated_signup_count
    }.to_i
  end
end
