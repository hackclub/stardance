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

  private

  def prepare_landing_page_state
    @new_onboarding = Flipper.enabled?(:new_onboarding)
    @rsvp_count = cached_rsvp_count unless @new_onboarding
  end

  def cached_rsvp_count
    Rails.cache.fetch("landing/rsvp_count", expires_in: 30.seconds) { Rsvp.count }
  end
end
