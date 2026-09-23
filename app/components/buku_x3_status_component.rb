# frozen_string_literal: true

# Private role reminder. Call sites pass the signed-in viewer, never a profile
# or project owner; do not cache this fragment across users.
class BukuX3StatusComponent < ViewComponent::Base
  def initialize(user:, compact: false, preview: false, preview_role: "buku")
    @user = user
    @compact = compact
    @preview = preview
    @preview_role = preview_role
  end

  def render?
    return true if preview?

    @user.present? && @user.onboarded? && Flipper.enabled?(:bukux3, @user) &&
      @user.has_dismissed?(VisualNovelComponent::BUKU_X3_DISMISS_THING) &&
      @user.has_dismissed?(BukuX3RevealComponent::DISMISS_THING)
  end

  def compact? = @compact
  def preview? = @preview && Rails.env.development?
  def buku?
    return @preview_role != "bean" if preview?

    @buku = BukuX3::Assignment.buku?(@user) unless defined?(@buku)
    @buku
  end
  def role_name = buku? ? "buku buku" : "bean"
  def icon = "events/bukux3/#{buku? ? 'buku' : 'bean'}.png"
  def reminder = "your hours will #{buku? ? 'destroy' : 'repair'} the spaceship"
  def percent = event&.percent || BukuX3::Event::STARTING_PERCENT
  def marker_position = 100 - percent
  def display_percent = helpers.number_with_precision(percent, precision: 1, strip_insignificant_zeros: true)
  def team_hours = @team_hours ||= event&.team_hours || { buku: 0, bean: 0 }
  def display_hours(team) = helpers.number_with_precision(team_hours.fetch(team), precision: 1, delimiter: ",", strip_insignificant_zeros: true)

  private
    def event = @event ||= BukuX3::Event.current
end
