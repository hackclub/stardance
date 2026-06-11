# Seeds post_views (and posts.views_count) from historical Ahoy feed events so
# existing posts don't launch with a zero view count.
#
# dry run:  bin/rails backfill:post_views
# to apply: bin/rails backfill:post_views DRY_RUN=false

namespace :backfill do
  desc "Backfill post_views and posts.views_count from Ahoy feed events"
  task post_views: :environment do
    # Without AHOY_DB_URL Ahoy tracking is a no-op store (see
    # config/initializers/ahoy.rb) and there are no events to backfill from.
    abort "AHOY_DB_URL is not set, so there is no Ahoy events database to backfill from." if ENV["AHOY_DB_URL"].blank?

    dry_run = ENV.fetch("DRY_RUN", "true") != "false"

    puts dry_run ? "[DRY RUN] No changes will be written." : "Writing changes to the database."
    puts

    post_id_sql = Arel.sql("properties->>'post_id'")
    events = Ahoy::Event
      .where.not(user_id: nil)
      .where("properties->>'post_id' IS NOT NULL")

    view_times = events
      .where(name: %w[feed_post_impression feed_post_read feed_post_open])
      .group(:user_id, post_id_sql)
      .minimum(:time)
    read_times = events
      .where(name: %w[feed_post_read feed_post_open])
      .group(:user_id, post_id_sql)
      .minimum(:time)

    post_ids = Post.where(id: view_times.keys.map(&:last).uniq).pluck(:id).to_set
    user_ids = User.where(id: view_times.keys.map(&:first).uniq).pluck(:id).to_set

    rows = view_times.filter_map do |(user_id, post_id), first_viewed_at|
      next unless post_ids.include?(post_id.to_i) && user_ids.include?(user_id)

      {
        post_id: post_id.to_i,
        user_id: user_id,
        read_at: read_times[[ user_id, post_id ]],
        created_at: first_viewed_at,
        updated_at: first_viewed_at
      }
    end

    # Views of a repost also credit the original post (see Post#view_credited_posts).
    repost_originals = Post
      .where(id: rows.map { |row| row[:post_id] }, postable_type: "Post::Repost")
      .joins("INNER JOIN post_reposts ON post_reposts.id = posts.postable_id")
      .pluck(:id, Arel.sql("post_reposts.original_post_id"))
      .to_h
    derived = rows.filter_map do |row|
      original_id = repost_originals[row[:post_id]]
      row.merge(post_id: original_id) if original_id
    end

    merged_rows = (rows + derived)
      .group_by { |row| [ row[:post_id], row[:user_id] ] }
      .map do |(post_id, user_id), dupes|
        first_viewed_at = dupes.map { |row| row[:created_at] }.min
        {
          post_id: post_id,
          user_id: user_id,
          read_at: dupes.filter_map { |row| row[:read_at] }.min,
          created_at: first_viewed_at,
          updated_at: first_viewed_at
        }
      end

    puts "#{view_times.size} unique (user, post) pairs in Ahoy, #{rows.size} match existing posts/users, " \
         "#{derived.size} credited to repost originals, #{merged_rows.size} rows after merging."

    unless dry_run
      merged_rows.each_slice(1_000) do |slice|
        PostView.insert_all(slice, unique_by: [ :post_id, :user_id ])
      end
      Post.connection.execute(<<~SQL.squish)
        UPDATE posts
        SET views_count = agg.views_count
        FROM (SELECT post_id, COUNT(*) AS views_count FROM post_views GROUP BY post_id) agg
        WHERE posts.id = agg.post_id
          AND posts.views_count IS DISTINCT FROM agg.views_count
      SQL
      puts "Inserted view rows and recounted posts.views_count."
    end

    puts "Run with DRY_RUN=false to apply." if dry_run
  end
end
