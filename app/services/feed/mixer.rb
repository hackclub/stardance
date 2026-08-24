# frozen_string_literal: true

require "zlib"

class Feed::Mixer
  GORSE_WEIGHT = 4
  RANK_BUCKET_SIZE = 5
  FIRST_PAGE_SIZE = 3
  PAGE_SIZE = 10
  FIRST_PAGE_SHIP_LIMIT = 1
  PAGE_SHIP_LIMIT = 2

  Result = Struct.new(:entries, :metrics, keyword_init: true)
  Entry = Struct.new(:post, :source, :content_id, keyword_init: true)

  def self.canonical_content_id(post)
    if post&.repost?
      post.postable&.original_post_id
    else
      post&.id
    end
  end

  def initialize(gorse_posts:, fresh_posts:, blocked_content_ids:, served_at:, seed:, max_items:)
    @gorse_posts = Array(gorse_posts)
    @fresh_posts = Array(fresh_posts)
    @blocked_content_ids = blocked_content_ids.to_set
    @served_at = served_at
    @seed = seed.to_s
    @max_items = max_items
    @metrics = {
      gorse_candidates: @gorse_posts.size,
      fresh_candidates: @fresh_posts.size,
      blocked_content: @blocked_content_ids.size,
      served_content: @served_at.size,
      author_project_relaxed: 0,
      ship_cap_relaxed: 0
    }
  end

  def call
    unseen_pool = candidate_pool(served: false)
    served_pool = candidate_pool(served: true).sort_by { |entry| served_at.fetch(entry.content_id, 0) }
    entries = select_pages(unseen_pool, served_pool)

    metrics.merge!(
      selected: entries.size,
      selected_by_source: entries.group_by(&:source).transform_values(&:size),
      selected_ships: entries.count { |entry| ship?(entry) },
      gorse_state: gorse_posts.any? ? "available" : "fallback"
    )

    Result.new(entries:, metrics:)
  end

  private
    attr_reader :gorse_posts, :fresh_posts, :blocked_content_ids, :served_at, :seed, :max_items, :metrics

    def candidate_pool(served:)
      gorse = lane_entries(bucket_shuffle(gorse_posts, "gorse"), "recommended", served:)
      fresh_source = gorse_posts.any? ? "fresh_explore" : "quality_latest_fallback"
      fresh = lane_entries(bucket_shuffle(fresh_posts, "fresh"), fresh_source, served:)
      interleave(gorse, fresh)
    end

    def bucket_shuffle(posts, lane)
      random = Random.new(Zlib.crc32("#{seed}:#{lane}"))
      posts.each_slice(RANK_BUCKET_SIZE).flat_map { |bucket| bucket.shuffle(random:) }
    end

    def lane_entries(posts, source, served:)
      posts.filter_map do |post|
        content_id = self.class.canonical_content_id(post)
        next unless eligible?(post, content_id)
        next if served_at.key?(content_id) != served

        Entry.new(post:, source: served ? "served_relaxed" : source, content_id:)
      end
    end

    def eligible?(post, content_id)
      return false if content_id.blank? || blocked_content_ids.include?(content_id)
      return false if post.postable.blank?
      return true unless post.postable_type == "Post::ShipEvent"

      post.postable.certification_status == "approved"
    end

    def interleave(gorse, fresh)
      result = []
      seen_content = Set.new

      while gorse.any? || fresh.any?
        GORSE_WEIGHT.times { append_next(result, gorse, seen_content) }
        append_next(result, fresh, seen_content)
        append_next(result, fresh, seen_content) if gorse.empty?
      end

      result
    end

    def append_next(result, lane, seen_content)
      while (entry = lane.shift)
        next if seen_content.include?(entry.content_id)

        seen_content << entry.content_id
        result << entry
        break
      end
    end

    def select_pages(unseen_pool, served_pool)
      selected = []
      page_index = 0

      while selected.size < max_items && (unseen_pool.any? || served_pool.any?)
        page_size = page_index.zero? ? FIRST_PAGE_SIZE : PAGE_SIZE
        target = [ page_size, max_items - selected.size ].min
        ship_limit = page_index.zero? ? FIRST_PAGE_SHIP_LIMIT : PAGE_SHIP_LIMIT
        page = []

        fill_page(page, unseen_pool, target, ship_limit)
        fill_page(page, served_pool, target, ship_limit) if page.size < target
        break if page.empty?

        selected.concat(page)
        page_index += 1
      end

      selected
    end

    def fill_page(page, pool, target, ship_limit)
      fill_pass(page, pool, target, ship_limit, enforce_diversity: true, enforce_ship_limit: true)

      if page.size < target
        added = fill_pass(page, pool, target, ship_limit, enforce_diversity: false, enforce_ship_limit: true)
        metrics[:author_project_relaxed] += added
      end

      if page.size < target
        added = fill_pass(page, pool, target, ship_limit, enforce_diversity: false, enforce_ship_limit: false)
        metrics[:ship_cap_relaxed] += added
      end
    end

    def fill_pass(page, pool, target, ship_limit, enforce_diversity:, enforce_ship_limit:)
      added = 0
      used_users = page.filter_map { |entry| entry.post.user_id }.to_set
      used_projects = page.filter_map { |entry| entry.post.project_id }.to_set
      ship_count = page.count { |entry| ship?(entry) }

      pool.dup.each do |entry|
        break if page.size >= target
        next if enforce_diversity && duplicate_origin?(entry, used_users, used_projects)
        next if enforce_ship_limit && ship?(entry) && ship_count >= ship_limit

        page << entry
        pool.delete(entry)
        used_users << entry.post.user_id if entry.post.user_id.present?
        used_projects << entry.post.project_id if entry.post.project_id.present?
        ship_count += 1 if ship?(entry)
        added += 1
      end

      added
    end

    def duplicate_origin?(entry, used_users, used_projects)
      (entry.post.user_id.present? && used_users.include?(entry.post.user_id)) ||
        (entry.post.project_id.present? && used_projects.include?(entry.post.project_id))
    end

    def ship?(entry)
      entry.post.postable_type == "Post::ShipEvent"
    end
end
