# frozen_string_literal: true

# Weekly "ship a project by the deadline for a free sticker" promo.
#
# To run the promo again, append a Week to WEEKS (oldest first, newest last).
# The last entry is the live one: it drives the countdown, the popup copy and
# the dismissal key, so appending automatically re-shows the popup to everyone
# who dismissed the previous week.
class StickerPromo
  Week = Data.define(:number, :deadline, :label, :window_start) do
    def initialize(number:, deadline:, label:, window_start: deadline - 7.days) = super

    def window = window_start...deadline

    def covers?(time) = window.cover?(time)
  end

  # Deadlines are the machine cutoff and are set in UTC. Labels are the
  # human-readable copy shown in the popup. A week opens 7 days before its
  # deadline unless window_start says otherwise.
  WEEKS = [
    Week.new(number: 1, deadline: Time.new(2026, 6, 30, 4, 59, 0, "+00:00"), label: "NEXT MONDAY (29th June 2359 EST)"),
    # Opens where week 1 closes rather than a full 7 days back, so the two
    # weeks don't both claim the 24 hours they were originally live for.
    Week.new(number: 2, deadline: Time.new(2026, 7, 6, 4, 59, 0, "+00:00"), label: "THIS SUNDAY (July 5th, 11:59 PM EST)",
             window_start: Time.new(2026, 6, 30, 4, 59, 0, "+00:00")),
    Week.new(number: 3, deadline: Time.new(2026, 7, 20, 4, 59, 0, "+00:00"), label: "THIS SUNDAY (July 19th, 11:59 PM EST)")
  ].freeze

  CURRENT_WEEK = WEEKS.last
  DEADLINE = CURRENT_WEEK.deadline
  DEADLINE_LABEL = CURRENT_WEEK.label

  class << self
    def active? = Time.current < DEADLINE

    # Start of the current promo week; used to check whether a user has shipped
    # a qualifying project in time for the sticker.
    def window_start = CURRENT_WEEK.window_start

    def deadline_iso = DEADLINE.iso8601

    # Week-scoped so each new DEADLINE is treated as a fresh, undismissed promo.
    def dismissal_key = "sticker_promo_#{DEADLINE.strftime('%Y_%m_%d')}"

    # Numbers of the promo weeks the user shipped in. Reads ship event posts
    # rather than projects.shipped_at, which submit_for_review overwrites on
    # every reship and withdraw_ship nulls, leaving nothing behind for the
    # earlier weeks.
    def weeks_for(user)
      shipped_at = Post.where(postable_type: "Post::ShipEvent")
                       .where(project_id: user.projects.where(deleted_at: nil).select(:id))
                       .where(created_at: WEEKS.first.window_start...WEEKS.last.deadline)
                       .pluck(:created_at)

      WEEKS.select { |week| shipped_at.any? { |time| week.covers?(time) } }.map(&:number)
    end
  end
end
