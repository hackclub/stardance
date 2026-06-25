# The product activation funnel, in order. Each step maps to the timestamp at
# which the user first reached it (nil if not reached yet). funnel_stage is the
# earliest step they HAVEN'T completed — the next action to nudge them toward —
# and funnel_stage_entered_at is when they last made forward progress (their
# "stuck since"). Because steps can be completed out of order (e.g. HCA can be
# linked before a project exists), we report the first *gap* rather than the
# furthest step reached, so a user who skipped an earlier step still gets
# nudged to fill it. Once every step is done the stage is :completed.
#
# Rails only reports *which* stage and *when* it was entered — it deliberately
# does not decide "stuck for 2 days" or send anything. That lives downstream:
# Airtable::UserSyncJob mirrors these two fields into the `_users` table, an
# Airtable formula derives days-in-stage, and the existing Airtable -> Loops
# sync sends a one-per-stage re-engagement nudge. Keeping the threshold out of
# Rails means no "have we already notified?" bookkeeping here.
module User::Funnel
  extend ActiveSupport::Concern

  # Canonical order. Mirrors the signup-funnel dashboard.
  STAGES = %i[
    signed_up
    onboarded
    project_created
    hca_linked
    hackatime_connected
    hackatime_project_linked
    devlog_posted
    shop_order_placed
    shipped
  ].freeze

  included do
    # Onboarding is the only funnel step recorded on the user record itself
    # (the rest are separate records — see FunnelResyncTrigger). Push the user
    # to the front of the Airtable sync queue when it flips.
    after_update_commit :flag_for_resync!, if: :saved_change_to_onboarded_at?
  end

  # The earliest funnel step the user hasn't completed — the next action to
  # nudge them toward — or :completed once every step is done.
  def funnel_stage = funnel_progress.first

  # When the user last made forward progress — their "stuck since".
  def funnel_stage_entered_at = funnel_progress.last

  # Force this user to the front of the Airtable sync queue: records_to_sync
  # orders by `synced_at ASC NULLS FIRST`, so nulling it makes the next
  # UserSyncJob run pick them up ahead of the round-robin. Called whenever a
  # funnel-advancing record is created (FunnelResyncTrigger) or onboarding
  # completes, so a stage change can't sit stale long enough to mis-fire a
  # re-engagement email. update_column = one cheap UPDATE, no callbacks.
  def flag_for_resync! = update_column(:synced_at, nil)

  private

  # [next_incomplete_step, last_progress_at]. signed_up is always present
  # (created_at), so the gap is never :signed_up; when there's no gap left the
  # user has finished the funnel and the stage is :completed.
  def funnel_progress
    timestamps = funnel_step_timestamps
    next_step = STAGES.find { |stage| timestamps[stage].nil? } || :completed
    [ next_step, timestamps.values.compact.max ]
  end

  def funnel_step_timestamps
    {
      signed_up: created_at,
      onboarded: onboarded_at,
      project_created: projects.minimum(:created_at),
      hca_linked: hack_club_identity&.created_at,
      hackatime_connected: hackatime_identity&.created_at,
      hackatime_project_linked: hackatime_projects.minimum(:created_at),
      devlog_posted: Post.where(user_id: id, postable_type: "Post::Devlog").minimum(:created_at),
      shop_order_placed: shop_orders.minimum(:created_at),
      shipped: Post.where(user_id: id, postable_type: "Post::ShipEvent").minimum(:created_at)
    }
  end
end
