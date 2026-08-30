class JellySyncJob < ApplicationJob
  queue_as :literally_whenever

  # Ceiling on how far one run will page. The first run backfills over several
  # runs rather than trying to walk the whole mailbox inside one job.
  MAX_PAGES = 40
  # Message paging is the expensive call (one request per conversation), so
  # only conversations that actually changed are re-read, and only this many
  # per run.
  MAX_MESSAGE_FETCHES = 150

  def perform(full: false)
    # A silent return here is indistinguishable from a sync that ran and found
    # nothing, which is exactly how this went unnoticed in production.
    unless Jelly::Client.configured?
      Rails.logger.warn("[JellySync] skipped: JELLY_API_TOKEN is not set")
      return
    end

    @client = Jelly::Client.new
    @started_at = Time.current
    watermark = full ? nil : JellyConversation.watermark

    sync_conversations(watermark)
    sync_messages
    record_daily_stat
  end

  private

  # Pages newest-first and stops at the watermark. Jelly returns conversations
  # in recency order, so once a page predates the last sync everything after it
  # does too.
  def sync_conversations(watermark)
    cursor = nil

    MAX_PAGES.times do
      page = @client.conversations(cursor: cursor)
      rows = Array(page["conversations"])
      break if rows.empty?

      rows.each { |row| upsert(row) }

      cursor = page["next_cursor"]
      break if cursor.blank?
      break if watermark && rows.all? { |row| parse_time(row["updated_at"])&.< watermark }
    end
  end

  def upsert(row)
    conversation = JellyConversation.find_or_initialize_by(jelly_id: row["id"].to_s)
    conversation.update!(
      status: row["status"].presence || "open",
      opened_at: parse_time(row["created_at"]),
      remote_updated_at: parse_time(row["updated_at"]),
      resolved_at: row["status"] == "archived" ? parse_time(row["updated_at"]) : nil,
      assignee_count: Array(row["assignees"]).size,
      synced_at: @started_at
    )
  end

  # Newest first, so a fresh install has useful recent numbers immediately and
  # backfills history over subsequent runs rather than blocking on it.
  def sync_messages
    JellyConversation.needing_message_sync
                     .order(remote_updated_at: :desc)
                     .limit(MAX_MESSAGE_FETCHES)
                     .to_a
                     .each { |conversation| sync_messages_for(conversation) }
  end

  # First response is the gap between the first inbound message and the first
  # outbound one after it, which is the only way to get it: Jelly exposes no
  # response-time field.
  def sync_messages_for(conversation)
    messages = fetch_all_messages(conversation.jelly_id)
    inbound = messages.select { |m| m[:inbound] }
    outbound = messages.reject { |m| m[:inbound] }
    first_inbound = inbound.first
    first_reply = first_inbound && outbound.find { |m| m[:at] >= first_inbound[:at] }

    conversation.update!(
      last_inbound_at: inbound.last&.dig(:at),
      last_outbound_at: outbound.last&.dig(:at),
      first_response_seconds: first_inbound && first_reply ? (first_reply[:at] - first_inbound[:at]).to_i : nil,
      messages_synced_at: @started_at
    )
  rescue Jelly::Client::Error => e
    Rails.logger.warn("[JellySync] messages for #{conversation.jelly_id} failed: #{e.message}")
  end

  def fetch_all_messages(jelly_id)
    cursor = nil
    collected = []

    MAX_PAGES.times do
      page = @client.messages(jelly_id, cursor: cursor)
      rows = Array(page["messages"])
      collected.concat(rows.filter_map { |row| normalise_message(row) })

      cursor = page["next_cursor"]
      break if cursor.blank?
    end

    collected.sort_by { |message| message[:at] }
  end

  # Jelly marks direction with a boolean `inbound`, and `sent_at` is when the
  # message actually went out. A message with no sent_at was never sent, so it
  # can't have answered anyone.
  def normalise_message(row)
    at = parse_time(row["sent_at"])
    return if at.nil?

    { at: at, inbound: row["inbound"] == true }
  end

  def record_daily_stat
    today = @started_at.to_date
    open_conversations = JellyConversation.open_now.to_a
    hangs = open_conversations.filter_map { |c| c.hang_seconds(now: @started_at) }
    responses = JellyConversation.where(opened_at: today.all_day)
                                 .where.not(first_response_seconds: nil)
                                 .pluck(:first_response_seconds)

    JellyDailyStat.record_for!(today,
      open_count: open_conversations.size,
      awaiting_reply_count: JellyConversation.awaiting_reply.count,
      arrivals: JellyConversation.where(opened_at: today.all_day).count,
      resolutions: JellyConversation.where(resolved_at: today.all_day).count,
      median_first_response_seconds: percentile(responses, 50),
      p95_hang_seconds: percentile(hangs, 95))
  end

  def percentile(values, percentile)
    return if values.blank?

    sorted = values.compact.sort
    sorted[((percentile / 100.0) * (sorted.size - 1)).round]&.to_i
  end

  def parse_time(value) = value.present? ? Time.zone.parse(value.to_s) : nil
end
