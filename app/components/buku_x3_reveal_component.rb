# frozen_string_literal: true

# One-time secret-role reveal for the :bukux3 event. Only the pseudorandomly
# assigned Buku Buku half sees the scene; the other half continues normally.
class BukuX3RevealComponent < ViewComponent::Base
  DISMISS_THING = "bukux3_role_reveal"

  attr_reader :user

  def initialize(user:, preview: false)
    @user = user
    @preview = preview
  end

  def render?
    return true if preview?

    user.present? &&
      user.onboarded? &&
      Flipper.enabled?(:bukux3, user) &&
      BukuX3::Assignment.buku?(user) &&
      !user.has_dismissed?(DISMISS_THING) &&
      !competing_intro_running?
  end

  def dismiss_thing = preview? ? nil : DISMISS_THING

  private
    def preview? = @preview && Rails.env.development?

    def competing_intro_running?
      welcome_tour_running? || visual_novel_running?
    end

    def welcome_tour_running?
      helpers.params[:welcome] == "1" && !user.has_dismissed?("home_intro")
    end

    def visual_novel_running?
      Flipper.enabled?(:bukux2, user) && !user.has_dismissed?(VisualNovelComponent::DISMISS_THING)
    end
end
