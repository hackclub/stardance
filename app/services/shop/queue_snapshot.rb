module Shop
  # Public picture of the shop order pipeline, backing the /queue transparency
  # page. The question it answers is "when does my thing actually get sent?",
  # so it is built around the whole journey rather than the review step alone:
  #
  #   placed → [in review] → approved → [packing & post] → sent
  #
  # Both legs are reported separately and as a total, because a buyer waiting
  # on a parcel cares about the sum but deserves to see which half they are
  # sitting in.
  #
  # Turnaround is aggregated in SQL so the page costs a handful of grouped
  # queries no matter how much order history exists. The only rows read back
  # whole are the open ones, which are bounded by the pipeline itself.
  class QueueSnapshot
    CACHE_KEY = "shop/queue_snapshot/v2".freeze
    CACHE_TTL = 5.minutes

    # Review turnaround shifts week to week, so it reads off a short window.
    # Fulfillment includes printing and posting, slow enough that a 30 day
    # window would leave most items without a usable sample.
    REVIEW_WINDOW = 30.days
    FULFILLMENT_WINDOW = 90.days

    # Under this many orders an "average" is one unlucky package rather than a
    # trend, so per-item figures below it are withheld instead of shown.
    MIN_SAMPLE = 3

    # The two stages an order sits in while staff still owe it something.
    #
    # `awaiting_verification*` and `on_hold` are deliberately excluded: those
    # wait on the buyer, not on us, so counting them would tell everyone else
    # that more orders are "ahead" of theirs than anybody is actually working
    # through.
    IN_REVIEW = "pending".freeze
    AWAITING_DISPATCH = "awaiting_periodical_fulfillment".freeze
    OPEN_STATES = [ IN_REVIEW, AWAITING_DISPATCH ].freeze

    STAGE_LABELS = {
      IN_REVIEW => "In review",
      AWAITING_DISPATCH => "Packing & post"
    }.freeze

    # Ageing bands the open pipeline is split across: (label, upper bound,
    # tone). The last band is open-ended, and the tones run cool to warm so
    # the distribution bar reads at a glance.
    AGE_BANDS = [
      [ "Under a day", 1.day, "mint" ],
      [ "1-3 days", 3.days, "blue" ],
      [ "3-7 days", 7.days, "peach" ],
      [ "Over a week", nil, "salmon" ]
    ].freeze

    # Items the shop doesn't list publicly — mission prizes, drafts,
    # accessories that aren't sold on their own — still sit in the pipeline,
    # but naming them here would leak them, so their rows fold into one
    # anonymous row.
    HIDDEN_ITEM_LABEL = "Other items".freeze

    ItemRow = Struct.new(:name, :open, :review_hours, :dispatch_hours, :fulfillment_hours, :sample, keyword_init: true)
    AgeBand = Struct.new(:label, :count, :share, :tone, keyword_init: true)
    Stage = Struct.new(:key, :label, :count, :oldest_at, keyword_init: true)

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
      open_ages
      review_stats
      dispatch_stats
      fulfillment_stats
      fulfilled_last_week
      stages
      age_bands
      items
      self
    end

    # ── Headline: how long the whole journey takes ──────────────────────────

    # Order placed to parcel sent. The number this page exists to publish.
    def fulfillment_average_hours = mean_hours(fulfillment_stats.values, min_sample: 1)

    # The two legs that make up the total above.
    def review_average_hours = mean_hours(review_stats.values, min_sample: 1)

    def dispatch_average_hours = mean_hours(dispatch_stats.values, min_sample: 1)

    def fulfilled_last_week
      @fulfilled_last_week ||= ShopOrder.where(fulfilled_at: (@now - 7.days)..).count
    end

    # ── The open pipeline ───────────────────────────────────────────────────

    def open_count = open_orders.size

    # One entry per stage, so the page can show where the open orders actually
    # are instead of implying they're all queued behind a reviewer.
    def stages
      @stages ||= OPEN_STATES.map do |state|
        rows = open_orders.select { |row| row[:state] == state }
        Stage.new(
          key: state,
          label: STAGE_LABELS.fetch(state),
          count: rows.size,
          oldest_at: rows.map { |row| row[:created_at] }.min
        )
      end
    end

    def oldest_open_at = open_times.min

    # How long the orders in the pipeline right now have been there, measured
    # from when they were placed — the elapsed time a buyer actually feels,
    # rather than time-in-current-stage.
    def average_open_hours
      return if open_ages.empty?

      (open_ages.sum / open_ages.size / 1.hour).round(1)
    end

    def age_bands
      @age_bands ||= begin
        lower = 0
        AGE_BANDS.map do |label, upper, tone|
          bound = upper&.to_i
          count = open_ages.count { |age| age >= lower && (bound.nil? || age < bound) }
          lower = bound
          AgeBand.new(label: label, count: count, share: share_of_open(count), tone: tone)
        end
      end
    end

    # ── Per item ────────────────────────────────────────────────────────────

    # One row per item that is either in the pipeline now or has moved through
    # it inside the window — an item with neither would be a row of dashes.
    def items
      @items ||= begin
        ids = (open_by_item.keys + review_stats.keys + dispatch_stats.keys + fulfillment_stats.keys).compact.uniq
        named = public_item_names(ids)

        rows = named.map { |id, name| item_row(name, [ id ]) }
        hidden_ids = ids - named.keys
        rows << item_row(HIDDEN_ITEM_LABEL, hidden_ids) if hidden_ids.any?

        rows.select { |row| row.open.positive? || row.sample.positive? }
            .sort_by { |row| [ -row.open, -row.sample, row.name.downcase ] }
      end
    end

    private

    def open_orders
      @open_orders ||= ShopOrder.where(aasm_state: OPEN_STATES)
                                .pluck(:shop_item_id, :created_at, :aasm_state)
                                .map { |item_id, created_at, state| { item_id: item_id, created_at: created_at, state: state } }
    end

    def open_times = @open_times ||= open_orders.map { |row| row[:created_at] }

    def open_ages = @open_ages ||= open_times.map { |created_at| @now - created_at }

    def open_by_item = @open_by_item ||= open_orders.group_by { |row| row[:item_id] }.transform_values(&:size)

    def share_of_open(count)
      return 0.0 if open_count.zero?

      (count * 100.0 / open_count).round(1)
    end

    # The names this page is allowed to print, mirroring the public shop
    # catalog (ShopItem.cached_shop_page_data) minus its `enabled` clause.
    #
    # `enabled` is deliberately left off: an order can only be created for an
    # item that was enabled at the time (ShopOrder#check_item_enabled), so any
    # name reaching this page was already public. Filtering on it would instead
    # hide the rows of people whose orders are in the pipeline right now for
    # something since sold out — the readers this page exists for.
    def public_item_names(ids)
      ShopItem.where(id: ids)
              .listed
              .published
              .buyable_standalone
              .where(mission_prize_only: false)
              .pluck(:id, :name)
              .to_h
    end

    # Leg one: order placed to reviewer verdict, whichever way the verdict
    # went — an order rejected after an hour and one approved after an hour
    # cost the buyer the same wait.
    #
    # Each query spells its own SQL out rather than taking a fragment as an
    # argument, so every piece is a literal or a constant static analysis can
    # resolve; nothing user-supplied reaches the query.
    def review_stats
      @review_stats ||= tally(
        ShopOrder
          .where("#{ShopOrder::DECIDED_AT_SQL} >= ?", @now - REVIEW_WINDOW)
          .where("#{ShopOrder::DECIDED_AT_SQL} > shop_orders.created_at")
          .group(:shop_item_id)
          .pluck(Arel.sql(
            "shop_orders.shop_item_id, COUNT(*), " \
            "AVG(EXTRACT(EPOCH FROM (#{ShopOrder::DECIDED_AT_SQL} - shop_orders.created_at)))"
          ))
      )
    end

    # Leg two: approved to actually in the post. This is the half the page
    # previously had no way to show, and it's usually the longer one.
    def dispatch_stats
      @dispatch_stats ||= tally(
        ShopOrder
          .where(fulfilled_at: (@now - FULFILLMENT_WINDOW)..)
          .where("shop_orders.fulfilled_at > shop_orders.awaiting_periodical_fulfillment_at")
          .group(:shop_item_id)
          .pluck(Arel.sql(
            "shop_orders.shop_item_id, COUNT(*), " \
            "AVG(EXTRACT(EPOCH FROM (shop_orders.fulfilled_at - shop_orders.awaiting_periodical_fulfillment_at)))"
          ))
      )
    end

    # Both legs together: placed to sent.
    def fulfillment_stats
      @fulfillment_stats ||= tally(
        ShopOrder
          .where(fulfilled_at: (@now - FULFILLMENT_WINDOW)..)
          .where("shop_orders.fulfilled_at > shop_orders.created_at")
          .group(:shop_item_id)
          .pluck(Arel.sql(
            "shop_orders.shop_item_id, COUNT(*), " \
            "AVG(EXTRACT(EPOCH FROM (shop_orders.fulfilled_at - shop_orders.created_at)))"
          ))
      )
    end

    # Shapes the grouped rows above into { shop_item_id => [count, avg_seconds] }.
    #
    # Every query drops orders whose end timestamp precedes its start rather
    # than averaging them in: backfills and out-of-order state stamps both
    # produce those, and one is enough to drag an item's average negative.
    # A NULL start (an order fulfilled without passing through the dispatch
    # queue) fails that comparison too, which is what we want.
    def tally(rows)
      rows.to_h { |item_id, count, seconds| [ item_id, [ count, seconds.to_f ] ] }
    end

    def item_row(name, ids)
      fulfillment = ids.filter_map { |id| fulfillment_stats[id] }

      ItemRow.new(
        name: name,
        open: ids.sum { |id| open_by_item.fetch(id, 0) },
        review_hours: mean_hours(ids.filter_map { |id| review_stats[id] }),
        dispatch_hours: mean_hours(ids.filter_map { |id| dispatch_stats[id] }),
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
