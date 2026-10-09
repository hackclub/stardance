class ShopOrderDailySummaryJob < ApplicationJob
  queue_as :literally_whenever

  include ActionView::Helpers::DateHelper

  SHOP_ORDER_CHANNEL_ID = "C09N1P69GKZ"

  def perform
    return unless Flipper.enabled?(:shop_order_daily_summary)

    message = build_message
    SendSlackDmJob.perform_later(SHOP_ORDER_CHANNEL_ID, message)
  end

  private

  ITEM_TYPE_LABELS = {
    "ShopItem::ThirdPartyPhysical" => "Third Party Physical",
    "ShopItem::HQMailItem" => "HQ Mail",
    "ShopItem::LetterMail" => "Letter Mail",
    "ShopItem::NonmachinableLetterMail" => "Nonmachinable Letter Mail",
    "ShopItem::StickyStreakSticker" => "Sticky Streak Sticker",
    "ShopItem::WarehouseItem" => "Warehouse",
    "ShopItem::FreeStickers" => "Free Stickers",
    "ShopItem::HCBGrant" => "HCB Grant",
    "ShopItem::HCBPreauthGrant" => "HCB Preauth Grant",
    "ShopItem::ThirdPartyDigital" => "Third Party Digital",
    "ShopItem::SpecialFulfillmentItem" => "Special Fulfillment",
    "ShopItem::Inkthreadable" => "Inkthreadable",
    "ShopItem::HackClubberItem" => "Hack Clubber",
    "ShopItem::Accessory" => "Accessory"
  }.freeze

  def build_message
    awaiting_orders = ShopOrder.where(aasm_state: "awaiting_periodical_fulfillment").real
    awaiting_with_items = awaiting_orders.joins(:shop_item)

    assigned_breakdown = awaiting_orders
      .where.not(assigned_to_user_id: nil)
      .group(:assigned_to_user_id)
      .count
    user_names = User.where(id: assigned_breakdown.keys).index_by(&:id)

    type_breakdown = awaiting_with_items.group("shop_items.type").count

    long_awaiting = awaiting_orders.where("shop_orders.awaiting_periodical_fulfillment_at < ?", 48.hours.ago)
    oldest_awaiting = awaiting_orders.order(:awaiting_periodical_fulfillment_at).first

    fulfilled_today = ShopOrder.real.where(aasm_state: "fulfilled", fulfilled_at: Time.current.beginning_of_day..Time.current.end_of_day).count
    total = awaiting_orders.count
    leaderboard = daily_leaderboard

    msg = <<~MSG
      *📦 Daily Shop Order Summary*

      *Overview*
      • Awaiting fulfillment: *#{total}*
      • Fulfilled today: *#{fulfilled_today}*

      *📋 By Type*
      #{format_type_breakdown(type_breakdown)}

      *⏰ Long Hang Time (>48h)*
      • Awaiting >48h: *#{long_awaiting.count}*
      #{oldest_awaiting&.awaiting_periodical_fulfillment_at ? "• Oldest: *#{time_ago_in_words(oldest_awaiting.awaiting_periodical_fulfillment_at)}* ago" : ""}

      *👤 Assigned to Users*
      #{format_assigned_breakdown(assigned_breakdown, user_names)}

      *🏆 Today's Leaderboard*
      #{format_leaderboard(leaderboard)}

      #{status_message(total)}
    MSG

    msg.strip
  end

  def format_type_breakdown(breakdown)
    return "_No orders awaiting fulfillment_" if breakdown.empty?

    breakdown.sort_by { |_, count| -count }.map do |type, count|
      label = ITEM_TYPE_LABELS[type] || type.demodulize.titleize
      "• #{label}: *#{count}*"
    end.join("\n")
  end

  def format_assigned_breakdown(breakdown, user_names)
    return "_No orders currently assigned_" if breakdown.empty?

    breakdown.sort_by { |_, count| -count }.map do |user_id, count|
      user = user_names[user_id]
      mention = user&.slack_id.present? ? "<@#{user.slack_id}>" : (user&.display_name || "User ##{user_id}")
      "• #{mention}: *#{count}* orders"
    end.join("\n")
  end

  def daily_leaderboard
    today = Time.current.beginning_of_day..Time.current.end_of_day

    versions = PaperTrail::Version
      .where(item_type: "ShopOrder", created_at: today)
      .where.not(whodunnit: nil)
      .where("object_changes ? 'aasm_state'")

    counts = versions.each_with_object(Hash.new(0)) do |version, tally|
      user_id = version.whodunnit.to_i
      next if user_id.zero?

      changes = version.object_changes
      next if changes.is_a?(String) && changes.start_with?("---")
      changes = JSON.parse(changes) if changes.is_a?(String)
      state_change = changes["aasm_state"]
      next unless state_change.is_a?(Array) && state_change[1] == "fulfilled"

      tally[user_id] += 1
    end

    top = counts.sort_by { |_, v| -v }.first(5)
    user_ids = top.map(&:first)
    users = User.where(id: user_ids).index_by(&:id)

    top.map do |(user_id, count)|
      user = users[user_id]
      mention = user&.slack_id.present? ? "<@#{user.slack_id}>" : (user&.display_name || "User ##{user_id}")
      { mention: mention, count: count }
    end
  end

  def format_leaderboard(entries)
    return "_No fulfillments today yet_" if entries.empty?

    medals = %w[🥇 🥈 🥉]
    entries.each_with_index.map do |entry, i|
      prefix = medals[i] || "#{i + 1}."
      "#{prefix} #{entry[:mention]} (#{entry[:count]})"
    end.join("\n")
  end

  def status_message(backlog)
    if backlog == 0
      "🎉 *All caught up!* No pending orders."
    elsif backlog < 10
      "📊 Almost there! Only *#{backlog}* orders to process."
    elsif backlog < 50
      "📊 *#{backlog}* orders in the queue. Let's keep it moving!"
    else
      "📊 *#{backlog}* orders waiting. Let's chip away at it! 💪"
    end
  end

end
