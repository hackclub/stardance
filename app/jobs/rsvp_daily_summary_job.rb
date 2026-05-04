class RsvpDailySummaryJob < ApplicationJob
  queue_as :default

  CHANNEL_ID = "C0AR0M43H61" # stardance-construction

  def perform
    return unless Flipper.enabled?(:rsvp_daily_summary)

    since = 1.day.ago
    SendSlackDmJob.perform_later(
      CHANNEL_ID,
      "Daily RSVP Summary",
      blocks_path: "notifications/rsvp_daily_summary",
      locals: build_locals(since)
    )
  end

  private

  def build_locals(since)
    new_rsvps = Rsvp.where(created_at: since..)

    ref_breakdown = new_rsvps.group(:ref).count.sort_by { |_, c| -c }

    first_seen_per_ref = Rsvp.group(:ref).minimum(:created_at)
    new_ref_names = first_seen_per_ref
      .select { |ref, first| ref.present? && first >= since }
      .keys
      .sort

    {
      total: Rsvp.count,
      new_count: new_rsvps.count,
      click_conf: Rsvp.where.not(click_confirmed_at: nil).count,
      reply_conf: Rsvp.where.not(reply_confirmed_at: nil).count,
      new_games: Rsvp::Game.where(created_at: since..).count,
      new_replies: Rsvp::Reply.where(created_at: since..).count,
      ref_breakdown: ref_breakdown,
      new_ref_names: new_ref_names,
      since: since
    }
  end
end
