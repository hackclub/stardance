class FraudDailySummaryJob < ApplicationJob
  queue_as :default

  FRAUD_CHANNEL_ID = "C0B239CM64W"

  include Rails.application.routes.url_helpers

  def perform
    return unless Flipper.enabled?(:fraud_daily_summary)

    stats = gather_stats
    message = build_message(stats)

    SendSlackDmJob.perform_later(FRAUD_CHANNEL_ID, message)
  end

  private

  def gather_stats
    today = Time.current.beginning_of_day..Time.current.end_of_day
    { shop_orders: gather_shop_order_stats(today) }
  end

  def gather_shop_order_stats(today)
    pending_orders = ShopOrder.real.where(aasm_state: "pending")
    awaiting_fulfillment = ShopOrder.real.where(aasm_state: "awaiting_periodical_fulfillment").count

    long_pending = pending_orders.where("shop_orders.created_at < ?", 48.hours.ago)
    oldest_pending = pending_orders.order(:created_at).first

    order_versions_today = PaperTrail::Version
      .where(item_type: "ShopOrder", created_at: today)
      .where.not(whodunnit: nil)
      .where("object_changes ? 'aasm_state'")

    leaderboard = build_leaderboard(order_versions_today)
    avg_response_time = calculate_avg_response_time_orders

    {
      new_today: ShopOrder.where(created_at: today).count,
      pending: pending_orders.count,
      awaiting_fulfillment: awaiting_fulfillment,
      backlog: pending_orders.count + awaiting_fulfillment,
      long_pending_count: long_pending.count,
      oldest_pending: oldest_pending,
      leaderboard: leaderboard,
      avg_response_hours: avg_response_time
    }
  end

  def build_leaderboard(versions)
    counts = versions.each_with_object(Hash.new(0)) do |version, tally|
      user_id = version.whodunnit.to_i
      next if user_id.zero?

      changes = version.object_changes || {}
      next if changes.is_a?(String) && changes.start_with?("---")
      changes = JSON.parse(changes) if changes.is_a?(String)
      state_change = changes["aasm_state"]
      next unless state_change.is_a?(Array) && state_change[1].in?(%w[awaiting_periodical_fulfillment rejected on_hold])

      tally[user_id] += 1
    end

    top = counts.sort_by { |_, v| -v }.first(5)
    users = User.where(id: top.map(&:first)).index_by(&:id)

    top.map do |(user_id, count)|
      user = users[user_id]
      mention = user&.slack_id.present? ? "<@#{user.slack_id}>" : (user&.display_name || "User ##{user_id}")
      { mention: mention, count: count }
    end
  end

  def calculate_avg_response_time_orders
    recent_orders = ShopOrder
      .where(aasm_state: %w[awaiting_periodical_fulfillment rejected fulfilled])
      .where("created_at > ?", 30.days.ago)
      .limit(100)

    return nil if recent_orders.empty?

    total_hours = recent_orders.sum do |order|
      first_action = order.versions.find do |v|
        changes = v.object_changes
        next if changes.is_a?(String) && changes.start_with?("---")
        changes = JSON.parse(changes) if changes.is_a?(String)
        changes&.dig("aasm_state")&.last.in?(%w[awaiting_periodical_fulfillment rejected])
      end
      next 0 unless first_action

      (first_action.created_at - order.created_at) / 1.hour
    end

    (total_hours / recent_orders.count).round(1)
  end

  def build_message(stats)
    orders = stats[:shop_orders]

    msg = <<~MSG
      *Daily Fraud Summary*

      *Overview*
      • New orders today: *#{orders[:new_today]}*
      • Pending review: *#{orders[:pending]}*
      • Awaiting fulfillment: *#{orders[:awaiting_fulfillment]}*
      #{orders[:avg_response_hours] ? "• Avg response time (30d): *#{orders[:avg_response_hours]}h*" : ""}

      *Long Hang Time (>48h)*
      • Pending >48h: *#{orders[:long_pending_count]}*
      #{orders[:oldest_pending]&.created_at ? "• Oldest: *#{time_ago_in_words(orders[:oldest_pending].created_at)}* ago" : ""}

      *Today's Reviewers*
      #{format_leaderboard(orders[:leaderboard])}

      #{status_message(orders[:backlog])}
    MSG

    msg.strip
  end


  def format_leaderboard(entries)
    return "_No reviews today yet_" if entries.empty?

    entries.each_with_index.map do |entry, i|
      "#{i + 1}. #{entry[:mention]} (#{entry[:count]})"
    end.join("\n")
  end

  def status_message(backlog)
    if backlog == 0
      "*Inbox zero.* Nothing pending."
    elsif backlog < 10
      "Only *#{backlog}* orders to review."
    elsif backlog < 50
      "*#{backlog}* orders in the queue."
    else
      "*#{backlog}* orders waiting."
    end
  end

  def time_ago_in_words(time)
    seconds = (Time.current - time).to_i
    if seconds < 3600
      "#{seconds / 60}m"
    elsif seconds < 86400
      "#{seconds / 3600}h"
    else
      "#{seconds / 86400}d #{(seconds % 86400) / 3600}h"
    end
  end
end
