# frozen_string_literal: true

# One-time role reveal, after the flag-enabled buku explanation.
class BukuX3RevealComponent < ViewComponent::Base
  DISMISS_THING = "bukux3_role_reveal"

  attr_reader :user

  def initialize(user:, preview: false, preview_role: :buku)
    @user = user
    @preview = preview
    @preview_role = preview_role
  end

  def render?
    return true if preview?

    user.present? &&
      user.onboarded? &&
      Flipper.enabled?(:bukux3, user) &&
      user.has_dismissed?(VisualNovelComponent::BUKU_X3_DISMISS_THING) &&
      !user.has_dismissed?(DISMISS_THING) &&
      !welcome_tour_running?
  end

  def dismiss_thing = preview? ? nil : DISMISS_THING

  def buku?
    return @preview_role != :bean if preview?

    @buku = BukuX3::Assignment.buku?(user) unless defined?(@buku)
    @buku
  end

  def role_name = buku? ? "buku buku" : "bean"
  def icon = "events/bukux3/#{buku? ? 'buku' : 'bean'}.png"
  def animation_url = helpers.asset_path("events/bukux3/shh-animated.webp")
  def description
    buku? ? "your hours will contribute to the destruction of the ship - make sure no stardancer will be able to return home!" :
      "your hours will contribute to fixing the rocket that'll take us all home. defeat the buku bukus!"
  end

  private
    def preview? = @preview && Rails.env.development?

    def welcome_tour_running?
      helpers.params[:welcome] == "1" && !user.has_dismissed?("home_intro")
    end
end
