# frozen_string_literal: true

# Visual-novel intro chapters behind their respective event flags. On any app
# page, the background is blurred and a speaker greets the user one line at a
# time, advanced with the arrow (or click / space / arrow key). The bukux3
# chapter leads into the role reveal when its flag is enabled.
#
# One line per box, so the script's own line breaks are its beats — the trailing
# dashes carry over into the next box. The portrait is a CSS sprite sheet (see
# _visual_novel.scss), not an image tag, because it animates. Dismissal is per
# account, so the scene plays once.
class VisualNovelComponent < ViewComponent::Base
  DISMISS_THING = "bukux2_intro"
  BUKU_X3_DISMISS_THING = "bukux3_intro"

  SPEAKER = "■ ■ ■"

  # %{name} is the viewer's display name. These run through format, so a literal
  # percent sign in the copy has to be escaped as %%.
  LINES = [
    "hi, %{name}! i'm here with a very special announcement -",
    "we're FINALLY going to space!",
    "except, there's a problem. the ship is in pieces!!!",
    "we need enough time to fix the rocket- every hour that YOU or any stardancer codes speeds up the build process!",
    "and once the ship is done, everyone who's contributed at least five hours - gets LIMITED-EDITION stickers :0 !!!!!!!!!! woah",
    "what do you think? let's get stardancing :D"
  ].freeze

  BUKU_X3_LINES = [
    "THE ROCKET SHIP IS COMPLETE! finally!",
    "!!!",
    "what's going on?? what -",
    "a BOMB? the buku bukus sent a BOMB?",
    "stardance is disintegrating and the rocket is FALLING APART, it's falling apart, holy crap",
    "help us fix the rocket so we can go home, or...",
    "!!!",
    "...or tear it apart so we'll keep stardancing forever...!",
    "will you be a bean or a buku buku?"
  ].freeze

  attr_reader :user

  def initialize(user:, chapter: :bukux2, preview: false)
    @user = user
    @chapter = chapter
    @preview = preview
    raise ArgumentError, "Unknown chapter" unless %i[bukux2 bukux3].include?(chapter)
  end

  def render?
    return true if preview?

    user.present? &&
      user.onboarded? &&
      Flipper.enabled?(@chapter, user) &&
      chapter_available? &&
      !user.has_dismissed?(dismiss_thing) &&
      !welcome_tour_running?
  end

  def speaker = buku_x3? ? "■■■" : SPEAKER
  def lines = buku_x3? ? BUKU_X3_LINES : LINES.map { |line| format(line, name: greeting_name) }
  def shake_lines = buku_x3? ? [ 1, 6 ] : []
  def dismiss_thing = preview? ? nil : (buku_x3? ? BUKU_X3_DISMISS_THING : DISMISS_THING)
  def skip_label = buku_x3? ? "skip" : "Skip"
  def next_label = buku_x3? ? "next line" : "Next line"
  def close_label = buku_x3? ? "reveal my role" : "Close"

  def next_scene_url
    return unless buku_x3?

    helpers.buku_x3_reveal_path(preview: preview? ? "buku" : nil)
  end

  private
    def buku_x3? = @chapter == :bukux3
    def preview? = @preview && Rails.env.development?

    def chapter_available?
      return true if buku_x3?

      # Don't tell late arrivals to repair a rocket that's already finished.
      !Flipper.enabled?(:bukux3, user)
    end

    # display_name is nullable, so fall back rather than greeting a blank.
    def greeting_name = user.display_name.presence || "stardancer"

    # The post-onboarding welcome tour (home#index, ?welcome=1) takes over the
    # whole page too — mirror its condition so the two scripted intros don't
    # fight over the screen.
    def welcome_tour_running?
      helpers.params[:welcome] == "1" && !user.has_dismissed?("home_intro")
    end
end
