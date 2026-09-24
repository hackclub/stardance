module Shop
  # Public picture of the shop order queue, backing the /queue transparency
  # page: how deep the backlog is, how long it has been waiting, and how long
  # each item has historically taken to review and to fulfill.
  #
  # Turnaround is aggregated in SQL so the page costs a handful of grouped
  # queries no matter how much order history exists. The only rows read back
  # whole are the pending ones, which are bounded by the backlog itself.
  class QueueSnapshot
    CACHE_KEY = "shop/queue_snapshot/v1".freeze
    CACHE_TTL = 5.minutes

    # Review turnaround shifts week to week, so it reads off a short window.
    # Fulfillment includes printing and posting, slow enough that a 30 day
    # window would leave most items without a usable sample.
    REVIEW_WINDOW = 30.days
    FULFILLMENT_WINDOW = 90.days

    # Under this many orders an "average" is one unlucky package rather than a
    # trend, so per-item figures below it are withheld instead of shown.
    MIN_SAMPLE = 3

    # Ageing bands the current backlog is split across: (label, upper bound,
    # tone). The last band is open-ended, and the tones run cool to warm so
    # the distribution bar reads at a glance.
    AGE_BANDS = [
      [ "Under a day", 1.day, "mint" ],
      [ "1-3 days", 3.days, "blue" ],
      [ "3-7 days", 7.days, "peach" ],
      [ "Over a week", nil, "salmon" ]
    ].freeze

    # Items the shop doesn't list publicly — mission prizes, retired stock,
    # drafts — still sit in the queue, but naming them here would leak them,
    # so their rows fold into a single anonymous one.
    HIDDEN_ITEM_LABEL = "Other items".freeze

    ItemRow = Struct.new(:name, :waiting, :review_hours, :fulfillment_hours, :sample, keyword_init: true)
    AgeBand = Struct.new(:label, :count, :share, :tone, keyword_init: true)

    attr_reader :generated_at

    # Memoised behind the cache so every visitor in a five minute window shares
    # one set of queries. `load!` runs the queries up front because the cache
    # stores the instance itself, not a lazily-evaluated promise.
    def self.cached
      Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { new.load! }
    end

    def initialize(now: Time.current)
      @now = now
      @generated_at = now
    end

    def load!
      backlog_ages
      review_stats
      fulfillment_stats
      decisions_last_week
      age_bands
      items
      self
    end

    def pending_count = backlog.size

    def oldest_waiting_at = backlog_times.min

    # How long the orders sitting in the queue right now have been there —
    # distinct from `review_average_hours`, which measures orders that have
    # already been dealt with.
    def average_wait_hours
      return if backlog_ages.empty?

      (backlog_ages.sum / backlog_ages.size / 1.hour).round(1)
    end

    def age_bands
      @age_bands ||= begin
        lower = 0
        AGE_BANDS.map do |label, upper, tone|
          bound = upper&.to_i
          count = backlog_ages.count { |age| age >= lower && (bound.nil? || age < bound) }
          lower = bound
          AgeBand.new(label: label, count: count, share: share_of_backlog(count), tone: tone)
        end
      end
    end

    def review_average_hours = mean_hours(review_stats.values, min_sample: 1)

    def fulfillment_average_hours = mean_hours(fulfillment_stats.values, min_sample: 1)

    def decisions_last_week
      @decisions_last_week ||= ShopOrder.where("#{ShopOrder::DECIDED_AT_SQL} >= ?", @now - 7.days).count
    end

    # One row per item that is either in the queue now or has moved through it
    # inside the window — an item with neither would be a row of dashes.
    def items
      @items ||= begin
        ids = (backlog_by_item.keys + review_stats.keys + fulfillment_stats.keys).compact.uniq
        named = ShopItem.where(id: ids).listed.published.pluck(:id, :name).to_h

        rows = named.map { |id, name| item_row(name, [ id ]) }
        hidden_ids = ids - named.keys
        rows << item_row(HIDDEN_ITEM_LABEL, hidden_ids) if hidden_ids.any?

        rows.select { |row| row.waiting.positive? || row.sample.positive? }
            .sort_by { |row| [ -row.waiting, -row.sample, row.name.downcase ] }
      end
    end

    private

    def backlog
      @backlog ||= ShopOrder.where(aasm_state: "pending").pluck(:shop_item_id, :created_at)
    end

    def backlog_times = @backlog_times ||= backlog.map(&:last)

    def backlog_ages = @backlog_ages ||= backlog_times.map { |created_at| @now - created_at }

    def backlog_by_item = @backlog_by_item ||= backlog.group_by(&:first).transform_values(&:size)

    def share_of_backlog(count)
      return 0.0 if pending_count.zero?

      (count * 100.0 / pending_count).round(1)
    end

    # Time from order placed to reviewer verdict, whichever way the verdict
    # went — an order rejected after an hour and one approved after an hour
    # cost the buyer the same wait.
    def review_stats
      @review_stats ||= turnaround(
        ShopOrder.where("#{ShopOrder::DECIDED_AT_SQL} >= ?", @now - REVIEW_WINDOW),
        ShopOrder::DECIDED_AT_SQL
      )
    end

    # Time from order placed to the item actually going out, which is the
    # number a buyer cares about: review plus packing plus dispatch.
    def fulfillment_stats
      @fulfillment_stats ||= turnaround(
        ShopOrder.where(fulfilled_at: (@now - FULFILLMENT_WINDOW)..),
        "fulfilled_at"
      )
    end

    # => { shop_item_id => [order_count, average_seconds] }
    #
    # Orders whose end timestamp precedes their creation are excluded rather
    # than averaged in: backfills and out-of-order state stamps both produce
    # them, and one is enough to drag an item's average negative.
    def turnaround(scope, finished_at_sql)
      rows = scope.where("#{finished_at_sql} > shop_orders.created_at")
                  .group(:shop_item_id)
                  .pluck(Arel.sql(<<~SQL.squish))
                    shop_orders.shop_item_id,
                    COUNT(*),
                    AVG(EXTRACT(EPOCH FROM (#{finished_at_sql} - shop_orders.created_at)))
                  SQL

      rows.to_h { |item_id, count, seconds| [ item_id, [ count, seconds.to_f ] ] }
    end

    def item_row(name, ids)
      fulfillment = ids.filter_map { |id| fulfillment_stats[id] }

      ItemRow.new(
        name: name,
        waiting: ids.sum { |id| backlog_by_item.fetch(id, 0) },
        review_hours: mean_hours(ids.filter_map { |id| review_stats[id] }),
        fulfillment_hours: mean_hours(fulfillment),
        sample: fulfillment.sum { |count, _seconds| count }
      )
    end

    # Averages arrive pre-grouped, so re-averaging them weights each group by
    # its order count rather than treating every group as a single point.
    def mean_hours(stats, min_sample: MIN_SAMPLE)
      orders = stats.sum { |count, _seconds| count }
      return if orders < min_sample

      (stats.sum { |count, seconds| count * seconds } / orders / 1.hour).round(1)
    end
  end
end
