class Airtable::UserSyncJob < Airtable::BaseSyncJob
  def table_name = "_users"

  # Only sync users with emails to avoid duplicate nil key issues in Airtable
  def records = User.where.not(email: [ nil, "" ])

  def primary_key_field = "email"

  # Backstop round-robin for the funnel-stuck nudges. Freshness for users who
  # actually advance is handled event-driven by FunnelResyncTrigger (their
  # synced_at is nulled, jumping them to the front); this limit just bounds how
  # long anything those hooks miss can stay stale. 100/min cycles ~29k users in
  # ~5h — well under the 2-day nudge window. Norairrecord's Faraday middleware
  # paces requests to Airtable's 5 req/s per-base limit on its own.
  def sync_limit = 100

  def field_mapping(user)
    address = user.addresses.first

    fields = {
      "first_name" => user.first_name,
      "last_name" => user.last_name,
      "email" => user.email,
      "slack_id" => user.slack_id,
      "avatar_url" => "https://cachet.dunkirk.sh/users/#{user.slack_id}/r",
      "has_commented" => user.comments.exists?,
      "has_some_role_of_access" => user.roles.any?,
      "hours" => user.all_time_coding_seconds&.fdiv(3600),
      "last_hackatime_activity_on" => user.last_hackatime_activity_on,
      "most_active_project" => user.most_active_project_title,
      "verification_status" => user.verification_status.to_s,
      "funnel_stage" => user.funnel_stage.to_s,
      "funnel_stage_entered_at" => user.funnel_stage_entered_at,
      "created_at" => user.created_at,
      "synced_at" => Time.now,
      "is_banned" => user.banned,
      "star_id" => user.id.to_s,
      "ref" => user.ref
    }

    if address.present?
      fields.merge!(
        "address_line_1" => address["line_1"],
        "address_line_2" => address["line_2"],
        "address_city" => address["city"],
        "address_state" => address["state"],
        "address_postal_code" => address["postal_code"],
        "address_country" => address["country"]
      )
    end

    fields.merge!(payout_loops_fields(user))
    fields
  end

  private

  # Payout notification data as Loops contact properties, synced through the
  # `_users` Airtable table (the only sanctioned path to Loops — no direct API).
  # `Loops - stardancePayoutIssuedAt` is the timestamp property a Loops workflow
  # (or a filtered campaign) fires on; Stardust/Project + the Rec1-3 items are
  # templated into the email. All of these `Loops - stardancePayout*` fields exist
  # on the `_users` table. Recommendations come from ShopItem.affordable_for (full
  # balance + region + wishlist + live catalog). Per-user latest payout only (one
  # row per user); blank for users with no genuine ship-event payout; fails closed
  # to {} so it can never break the sync.
  def payout_loops_fields(user)
    # Only genuine positive payouts drive the email. Ship-event ledger entries
    # also include clawbacks (created_by "manual_ship_event_payout_reversal",
    # negative amount); if a reversal were the user's latest entry the email
    # would announce e.g. "-9 stardust", so scope to real payouts of amount > 0.
    entry = user.ledger_entries
                .where(ledgerable_type: "Post::ShipEvent", created_by: "ship_event_payout")
                .where("amount > 0")
                .order(created_at: :desc)
                .first
    return {} unless entry

    fields = {
      "Loops - stardancePayoutIssuedAt" => entry.created_at&.iso8601,
      "Loops - stardancePayoutStardust" => entry.amount&.to_i,
      "Loops - stardancePayoutProject"  => entry.ledgerable&.project&.title
    }

    urls     = Rails.application.routes.url_helpers
    opts     = ActionMailer::Base.default_url_options
    host     = opts[:host] || "stardance.hackclub.com"
    protocol = opts[:protocol] || "https"

    ShopItem.affordable_for(user, limit: 3).each_with_index do |item, i|
      n = i + 1
      fields["Loops - stardancePayoutRec#{n}Name"]  = item.name
      fields["Loops - stardancePayoutRec#{n}Price"] = item.recommended_price
      fields["Loops - stardancePayoutRec#{n}Url"]   = urls.shop_item_url(item, host:, protocol:)
    end

    fields
  rescue => e
    # Fail closed so a bad lookup never breaks the whole sync, but make it loud:
    # a systemic break here (renamed Airtable field, changed route, bad data)
    # silently drops the payout-email trigger for everyone, so surface it via
    # Sentry rather than a warn line no one reads.
    Rails.logger.error("UserSyncJob payout_loops_fields failed for user #{user.id}: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    {}
  end
end
