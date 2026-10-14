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
  # Everything is aggregated in SQL so the page costs a handful of queries no
  # matter how much order history exists. The only rows read back whole are the
  # open ones, which are bounded by the pipeline itself.
  class QueueSnapshot
    CACHE_KEY = "shop/queue_snapshot/v3".freeze
    CACHE_TTL = 5.minutes

    # One cohort drives every duration on the page: orders actually sent in
    # this window. Reporting the legs and the total off a single cohort keeps
    # them addable — "4 days, of which 1 was review" only means anything when
    # both come from the same set of orders.
    SENT_WINDOW = 90.days

    # Under this many orders a per-item figure is one unlucky package rather
    # than a trend, so it is withheld instead of shown.
    MIN_SAMPLE = 3

    # Rows that live in shop_orders but are not somebody waiting on a shop
    # purchase. Leaving them in makes every headline on this page wrong:
    #
    # - StickyStreakSticker: daily-challenge rewards, batch-posted. They park
    #   in awaiting_periodical_fulfillment in enormous numbers (~10k, none ever
    #   fulfilled), which swamps the real queue by more than twenty to one.
    # - TutorialNothing: the shop tutorial's no-op "order". Not a purchase.
    # - FreeStickers: auto-marked fulfilled the moment they're approved, so
    #   their fulfilled_at is an approval timestamp, not a postmark. Counting
    #   them would make "placed to sent" a claim we can't stand behind, and
    #   they're numerous enough to halve the headline on their own.
    EXCLUDED_ITEM_TYPES = %w[
      ShopItem::StickyStreakSticker
      ShopItem::TutorialNothing
      ShopItem::FreeStickers
    ].freeze

    # The two stages an order sits in while staff still owe it something.
    #
    # `awaiting_verification*` and `on_hold` are deliberately excluded: those
    # wait on the buyer, not on us, so counting them would tell everyone else
    # that more orders are "ahead" of theirs than anybody is working through.
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

    ItemRow = Struct.new(:name, :open, :review_hours, :dispatch_hours, :total_hours, :sample, keyword_init: true)
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
      overall
      by_item
      sent_last_week
      stages
      age_bands
      items
      self
    end

    # ── Headline: how long the whole journey takes ──────────────────────────
    #
    # Medians, not means. The spread is enormous — a handful of orders take
    # months — and a mean lands on a duration almost nobody experiences.

    def total_median_hours = overall[:total]

    def review_median_hours = overall[:review]

    def dispatch_median_hours = overall[:dispatch]

    def sent_last_week
      @sent_last_week ||= sellable.where(fulfilled_at: (@now - 7.days)..).count
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
    def median_open_hours
      return if open_ages.empty?

      sorted = open_ages.sort
      middle = sorted.size / 2
      seconds = sorted.size.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0
      (seconds / 1.hour).round(1)
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

    # One row per item that is either in the pipeline now or has been sent
    # inside the window — an item with neither would be a row of dashes.
    def items
      @items ||= begin
        ids = (open_by_item.keys + by_item.keys).compact.uniq
        named = public_item_names(ids)

        rows = named.map { |id, name| item_row(name, [ id ]) }
        hidden_ids = ids - named.keys
        rows << item_row(HIDDEN_ITEM_LABEL, hidden_ids) if hidden_ids.any?

        rows.select { |row| row.open.positive? || row.sample.positive? }
            .sort_by { |row| [ -row.open, -row.sample, row.name.downcase ] }
      end
    end

    private

    # Every query on this page runs through here, so the exclusions above can
    # never be forgotten at one call site.
    def sellable
      ShopOrder.joins(:shop_item).where.not(shop_items: { type: EXCLUDED_ITEM_TYPES })
    end

    def open_orders
      @open_orders ||= sellable.where(aasm_state: OPEN_STATES)
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

    # Orders sent inside the window: the cohort every duration is read off.
    # Rows whose end timestamp precedes its start are dropped rather than
    # measured — backfills and out-of-order state stamps both produce those.
    def sent_cohort
      sellable.where(fulfilled_at: (@now - SENT_WINDOW)..)
              .where("shop_orders.fulfilled_at > shop_orders.created_at")
    end

    # PERCENTILE_CONT skips NULL inputs, so the dispatch leg simply ignores
    # orders that never passed through the dispatch queue instead of counting
    # them as instant.
    MEDIAN_COLUMNS = <<~SQL.squish.freeze
      COUNT(*),
      PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY EXTRACT(EPOCH FROM (shop_orders.fulfilled_at - shop_orders.created_at))),
      PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY EXTRACT(EPOCH FROM (COALESCE(shop_orders.rejected_at, shop_orders.awaiting_periodical_fulfillment_at, shop_orders.fulfilled_at) - shop_orders.created_at))),
      PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY EXTRACT(EPOCH FROM (shop_orders.fulfilled_at - shop_orders.awaiting_periodical_fulfillment_at)))
    SQL

    # Medians can't be recombined from per-item medians, so the headline is its
    # own ungrouped query rather than a roll-up of the table below.
    def overall
      @overall ||= begin
        count, total, review, dispatch = sent_cohort.pluck(Arel.sql(MEDIAN_COLUMNS)).first
        {
          sample: count.to_i,
          total: hours(total, count),
          review: hours(review, count),
          dispatch: hours(dispatch, count)
        }
      end
    end

    # => { shop_item_id => { sample:, total:, review:, dispatch: } }
    def by_item
      @by_item ||= sent_cohort
        .group(:shop_item_id)
        .pluck(Arel.sql("shop_orders.shop_item_id, #{MEDIAN_COLUMNS}"))
        .to_h do |item_id, count, total, review, dispatch|
          [ item_id, { sample: count.to_i, total: hours(total, count), review: hours(review, count), dispatch: hours(dispatch, count) } ]
        end
    end

    def hours(seconds, count, min_sample: 1)
      return if seconds.nil? || count.to_i < min_sample

      (seconds.to_f / 1.hour).round(1)
    end

    def item_row(name, ids)
      stats = ids.filter_map { |id| by_item[id] }
      sample = stats.sum { |stat| stat[:sample] }
      # Several ids only fold together on the anonymous row; medians don't
      # combine, so the largest contributor stands in for the group.
      leader = stats.max_by { |stat| stat[:sample] } || {}
      enough = sample >= MIN_SAMPLE

      ItemRow.new(
        name: name,
        open: ids.sum { |id| open_by_item.fetch(id, 0) },
        review_hours: (leader[:review] if enough),
        dispatch_hours: (leader[:dispatch] if enough),
        total_hours: (leader[:total] if enough),
        sample: sample
      )
    end
  end
end
