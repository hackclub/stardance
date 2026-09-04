# frozen_string_literal: true

# Visual-novel style intro dialogue. Behind the :bukux2 flag: on any app page,
# the page behind is blurred out and a speaker greets the user one line at a
# time, advanced with the arrow (or click / space / arrow key).
#
# One line per box, so the script's own line breaks are its beats — the trailing
# dashes carry over into the next box. The portrait is a CSS sprite sheet (see
# _visual_novel.scss), not an image tag, because it animates. Dismissal is per
# account, so the scene plays once.
class VisualNovelComponent < ViewComponent::Base
  DISMISS_THING = "bukux2_intro"

  SPEAKER = "meghana"

  # %{name} is the viewer's display name. These run through format, so a literal
  # percent sign in the copy has to be escaped as %%.
  LINES = [
    "hi, %{name}! i'm here with a very special announcement -",
    "we're FINALLY going to space!",
    "except, there's a problem. the ship is in pieces!!!",
    "we need enough time to fix the rocket- every hour that YOU or any stardancer codes speeds up the build process!",
    "and once the ship is done, everyone who's contributed at least five hours - gets a LIMITED-EDITION sticker :0 !!!!!!!!!! woah",
    "what do you think? let's get stardancing :D"
  ].freeze

  # TEMPORARY, for testing the scene: while this is true the dialogue replays on
  # every page load and finishing it records no dismissal. Set it to false (or
  # delete this accessor and its two callers below) before shipping the flag.
  class << self
    attr_accessor :replay_every_load
  end
  self.replay_every_load = true

  attr_reader :user

  def initialize(user:)
    @user = user
  end

  def render?
    user.present? &&
      user.onboarded? &&
      Flipper.enabled?(:bukux2, user) &&
      (replaying? || !user.has_dismissed?(DISMISS_THING)) &&
      !welcome_tour_running?
  end

  def speaker = SPEAKER
  def lines = LINES.map { |line| format(line, name: greeting_name) }

  # Blank while replaying, which is the controller's signal to skip the
  # dismissal POST — so a test run never marks the scene as seen.
  def dismiss_thing = replaying? ? "" : DISMISS_THING

  private
    def replaying? = self.class.replay_every_load

    # display_name is nullable, so fall back rather than greeting a blank.
    def greeting_name = user.display_name.presence || "stardancer"

    # The post-onboarding welcome tour (home#index, ?welcome=1) takes over the
    # whole page too — mirror its condition so the two scripted intros don't
    # fight over the screen.
    def welcome_tour_running?
      helpers.params[:welcome] == "1" && !user.has_dismissed?("home_intro")
    end
end
