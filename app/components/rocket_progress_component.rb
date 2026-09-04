# frozen_string_literal: true

# Pinned strip at the top of the home feed: how many approved hours the program
# has banked toward repairing Vega's rocket. Same story as the :bukux2 intro
# dialogue, so it hides with that flag and the home page is untouched without
# it.
#
# The figure comes from RocketProgress, which derives it from approved YSWS
# submissions inside the campaign window — nothing here writes anything.
class RocketProgressComponent < ViewComponent::Base
  attr_reader :user

  def initialize(user:)
    @user = user
  end

  def render? = Flipper.enabled?(:bukux2, user)

  def progress = @progress ||= RocketProgress.snapshot

  def hours = progress.hours
  def goal = progress.goal_hours
  def remaining = progress.remaining_hours
  def complete? = progress.complete?

  # Whole hours read better on a 500-hour goal; the exact figure still goes to
  # the progress bar's aria-valuenow.
  def display_hours = helpers.number_with_delimiter(hours.round)
  def display_goal = helpers.number_with_delimiter(goal)
  def display_remaining = helpers.number_with_delimiter(remaining.ceil)
end
