module Privacy
  class Eraser
    Result = Data.define(:found, :deleted, :retained)

    class DependencyUnavailable < StandardError; end

    OPEN_ORDER_STATES = %w[pending awaiting_verification awaiting_verification_call awaiting_periodical_fulfillment on_hold].freeze
    CANCELLATION_REASON = "Cancelled: account deleted after a privacy request".freeze
    PLACEHOLDER = "kept as an anonymous placeholder".freeze

    OWNED = [
      User::Identity, User::Preference, User::NotificationPreference, UserActivityDay, User::VoteVerdict, User::HackatimeProject,
      User::DataExport, Certificate, ProjectFollow, Project::Skip, Project::Membership, DailyRoll, MihiActivation, ExtensionUsage,
      Vote::Assignment, BukuX3::Contribution, Workshop::Rsvp, Workshop::Attendance, Mission::Membership, Certification::ReviewSkip,
      StreakActivity, ShopWishlist, Message
    ].freeze

    SCRUBBED = {
      Project => { title: "Deleted project", description: nil, demo_url: nil, readme_url: nil, repo_url: nil, ai_declaration: nil, update_description: nil },
      Post::ShipEvent => { body: nil, feedback_video_url: nil },
      Post::Devlog => { body: nil },
      ShopSuggestion => { name: "Deleted suggestion", description: nil, url: nil },
      Vote => { reason: nil },
      Raffle::Participant => { github_uid: nil, github_login: nil, github_avatar_url: nil }
    }.freeze

    # [type, reason, table, condition]; :users binds the erased user ids
    RETAINED = [
      [ "account record", "#{PLACEHOLDER} so financial records stay linked; names, emails, Slack ID, location, tokens and login identities removed", "users", "id IN (:users)" ],
      [ "cancelled shop orders", "unfulfilled orders are rejected so nothing ships to a deleted account; no refund, since the balance goes with the account",
        "shop_orders", "user_id IN (:users) AND aasm_state IN (:open)" ],
      [ "shop orders", "kept for accounting, fulfilment and customs, with the shipping address frozen on each order", "shop_orders" ],
      [ "warehouse packages", "kept for customs and carrier claims", "shop_warehouse_packages" ],
      [ "card grants", "HCB grant records kept for accounting", "shop_card_grants" ],
      [ "hardware funding requests", "HCB grant records kept for accounting", "certification_funding_requests" ],
      [ "ledger entries", "the stardust ledger is immutable and must balance", "ledger_entries" ],
      [ "payout lines", "fulfillment and fraud review payouts kept for accounting",
        "(SELECT user_id FROM fulfillment_payout_lines UNION ALL SELECT user_id FROM fraud_payout_lines) lines" ],
      [ "reviewer payout requests", "financial records kept for accounting; pending requests are rejected", "reviewer_payout_requests" ],
      [ "show and tell attendances", "kept because payouts reference them", "show_and_tell_attendances" ],
      [ "mission prize redemptions", "kept because shop orders and the ledger reference them", "mission_prize_redemptions" ],
      [ "achievements", "kept because rewards in the ledger reference them", "user_achievements" ],
      [ "sticky streaks", "streaks with claimed rewards are kept because shop orders reference them",
        "sticky_streaks", "user_id IN (:users) AND id IN (SELECT sticky_streak_id FROM sticky_streak_claims)" ],
      [ "votes cast", "kept so other projects' rankings and payouts stay stable; written reasons removed", "votes" ],
      [ "shop suggestion votes", "kept because they rank other people's suggestions and can carry stardust", "shop_suggestion_votes" ],
      [ "shop suggestions", "#{PLACEHOLDER} because votes and stardust reference them; text, link and image removed, pending ones rejected", "shop_suggestions" ],
      [ "reports filed", "kept for fraud prevention", "project_reports", "reporter_id IN (:users)" ],
      [ "fraud reviews about them", "kept for fraud prevention",
        "(SELECT subject_id AS user_id FROM fraud_review_payouts UNION ALL SELECT subject_id FROM fraud_subject_claims) reviews" ],
      [ "reviews of their submissions", "kept as the record of staff decisions about their projects", "certification_ysws_reviews" ],
      [ "review records they made", "kept because they are decisions about other people's work",
        "(SELECT reviewer_id AS user_id FROM certification_ship_reviews UNION ALL SELECT reviewer_id FROM certification_ysws_reviews " \
        "UNION ALL SELECT author_id FROM certification_review_notes UNION ALL SELECT user_id FROM shop_order_reviews " \
        "UNION ALL SELECT reviewer_id FROM fraud_review_payouts) reviews" ],
      [ "raffle wins", "#{PLACEHOLDER} because draws reference them; GitHub details removed", "raffle_participants",
        "user_id IN (:users) AND (id IN (SELECT winner_participant_id FROM raffle_draws) OR id IN (SELECT winner_participant_id FROM raffle_weeks))" ],
      [ "raffle referrals", "kept because they count toward the person who referred them", "raffle_referrals", "referred_user_id IN (:users)" ],
      [ "airtable copies", "not touched here; the privacy hub's Airtable target deletes them", "users", "id IN (:users) AND synced_at IS NOT NULL" ]
    ].freeze

    def initialize(subject)
      @subject = subject
    end

    def user_ids
      @user_ids ||= matching_user_ids
    end

    # staff accounts and sellers have things other people depend on, so a human decides
    def manual_review_required?
      User.where(id: user_ids).where("cardinality(granted_roles) > 0").exists? || ShopItem.where(user_id: user_ids).exists?
    end

    def call(dry_run:, request_id:)
      return Result.new(found: false, deleted: {}, retained: []) if user_ids.empty?

      @deleted = Hash.new(0)
      retained = retained_counts
      ActiveRecord::Base.transaction(requires_new: true) do
        erase!
        erase_analytics!(dry_run:)
        raise ActiveRecord::Rollback if dry_run

        erase_external!
        record_erasure!(request_id)
      end

      Result.new(found: true, deleted: @deleted.select { |_, count| count.positive? }, retained:)
    end

    private

    def matching_user_ids
      scope = User.none
      scope = scope.or(User.where("lower(email) IN (:e) OR lower(guest_email) IN (:e) OR lower(hcb_email) IN (:e)", e: @subject.emails)) if @subject.emails.any?
      scope = scope.or(User.where(slack_id: @subject.slack_id)) if @subject.slack_id
      scope = scope.or(User.where(id: User::Identity.where(provider: "hack_club", uid: @subject.identity_id).select(:user_id))) if @subject.identity_id
      scope.pluck(:id)
    end

    def retained_counts
      counts = RETAINED.map do |type, reason, table, condition = "user_id IN (:users)"|
        { type:, count: select_ids([ "SELECT count(*) FROM #{table} WHERE #{condition}", { users: user_ids, open: OPEN_ORDER_STATES } ]).first, reason: }
      end
      counts << { type: "projects", count: sole_project_ids.size,
                  reason: "hidden and #{PLACEHOLDER} because ship events, votes and payouts reference them; title, description, links, banner, demo video, devlogs and commits removed" }
      counts << { type: "reviewed devlogs", count: reviewed_devlog_ids.size,
                  reason: "hidden and #{PLACEHOLDER} because YSWS reviews reference them; text, attachments and edit history removed" }
      counts.select { |entry| entry[:count].positive? }
    end

    def erase!
      # read before the rows they come from go
      emails
      member_project_ids
      @hackatime_uids = connection.select_values(sanitize([ "SELECT uid FROM user_identities WHERE provider = 'hackatime' AND user_id IN (?)", user_ids ]))

      erase_attachments!
      erase_posts!
      erase_owned_records!
      erase_by_email!
      scrub_placeholders!
      close_open_work!
      anonymize_users!
      recount!
    end

    # projects where every current member is being erased
    def sole_project_ids
      @sole_project_ids ||= select_ids([ <<~SQL, user_ids, user_ids ])
        SELECT DISTINCT project_id FROM project_memberships m
        WHERE m.user_id IN (?) AND NOT EXISTS (
          SELECT 1 FROM project_memberships o WHERE o.project_id = m.project_id AND o.user_id NOT IN (?)
        )
      SQL
    end

    def member_project_ids
      @member_project_ids ||= select_ids([ "SELECT DISTINCT project_id FROM project_memberships WHERE user_id IN (?)", user_ids ])
    end

    # their devlogs and commits anywhere, plus everyone's in projects that are going away,
    # as [post id, postable type, postable id, project id]
    def removable_posts
      @removable_posts ||= connection.select_rows(sanitize([ <<~SQL, sole_project_ids, user_ids ])).map { |id, type, postable_id, project_id| [ id.to_i, type, postable_id.to_i, project_id&.to_i ] }
        SELECT id, postable_type, postable_id, project_id FROM posts
        WHERE postable_type IN ('Post::Devlog', 'Post::GitCommit') AND (project_id IN (?) OR user_id IN (?))
      SQL
    end

    def removable(type) = removable_posts.filter_map { |_, postable_type, id| id if postable_type == type }
    def devlog_ids = removable("Post::Devlog")

    # YSWS reviews hold a foreign key to these, so they stay as hidden placeholders
    def reviewed_devlog_ids
      @reviewed_devlog_ids ||= select_ids([ "SELECT DISTINCT post_devlog_id FROM certification_devlog_reviews WHERE post_devlog_id IN (?)", devlog_ids ])
    end

    def removed_post_ids
      @removed_post_ids ||= removable_posts.reject { |_, type, id| type == "Post::Devlog" && reviewed_devlog_ids.include?(id) }.map(&:first)
    end

    def sole_ship_event_ids
      @sole_ship_event_ids ||= select_ids([ "SELECT postable_id FROM posts WHERE postable_type = 'Post::ShipEvent' AND project_id IN (?)", sole_project_ids ])
    end

    def removed_repost_ids
      @removed_repost_ids ||= select_ids([ "SELECT id FROM post_reposts WHERE user_id IN (?) OR original_post_id IN (?)", user_ids, removed_post_ids ])
    end

    def removed_repost_post_ids
      @removed_repost_post_ids ||= select_ids([ "SELECT id FROM posts WHERE postable_type = 'Post::Repost' AND postable_id IN (?)", removed_repost_ids ])
    end

    def erase_attachments!
      attached = polymorphic("record",
                             "User" => user_ids, "Project" => sole_project_ids, "Post::Devlog" => devlog_ids, "Post::ShipEvent" => sole_ship_event_ids,
                             "User::DataExport" => select_ids([ "SELECT id FROM user_data_exports WHERE user_id IN (?)", user_ids ]),
                             "ShopSuggestion" => select_ids([ "SELECT id FROM shop_suggestions WHERE user_id IN (?)", user_ids ]))
      root_ids = select_where("SELECT DISTINCT blob_id FROM active_storage_attachments", attached)
      delete_where("active_storage_attachments", attached)
      # a blob still attached to something else stays
      blob_ids = with_derived_blobs(root_ids - select_ids([ "SELECT blob_id FROM active_storage_attachments WHERE blob_id IN (?)", root_ids ]))
      @blobs = ActiveStorage::Blob.where(id: blob_ids).to_a

      delete_where("active_storage_attachments", [ "blob_id IN (?)", blob_ids ])
      delete_where("active_storage_variant_records", [ "blob_id IN (?)", blob_ids ])
      delete_where("active_storage_blobs", [ "id IN (?)", blob_ids ])
    end

    # variant and preview images are blobs of their own
    def with_derived_blobs(blob_ids)
      frontier = blob_ids
      while frontier.any?
        variant_ids = select_ids([ "SELECT id FROM active_storage_variant_records WHERE blob_id IN (?)", frontier ])
        frontier = select_where("SELECT blob_id FROM active_storage_attachments",
                                polymorphic("record", "ActiveStorage::VariantRecord" => variant_ids, "ActiveStorage::Blob" => frontier)) - blob_ids
        blob_ids += frontier
      end
      blob_ids
    end

    def erase_posts!
      comment_ids = select_ids([ "SELECT id FROM comments WHERE user_id IN (?) OR (commentable_type = 'Post::Devlog' AND commentable_id IN (?))", user_ids, devlog_ids ])
      like_ids = select_ids([ "SELECT id FROM likes WHERE user_id IN (?) OR (likeable_type = 'Post::Devlog' AND likeable_id IN (?))", user_ids, devlog_ids ])
      post_ids = removed_post_ids + removed_repost_post_ids
      @recount_devlog_ids = select_ids([ <<~SQL, like_ids, comment_ids ]) - devlog_ids
        SELECT likeable_id FROM likes WHERE likeable_type = 'Post::Devlog' AND id IN (?)
        UNION SELECT commentable_id FROM comments WHERE commentable_type = 'Post::Devlog' AND id IN (?)
      SQL
      @recount_post_ids = select_ids([ <<~SQL, removed_repost_ids, user_ids ]) - post_ids
        SELECT original_post_id FROM post_reposts WHERE id IN (?)
        UNION SELECT post_id FROM post_views WHERE user_id IN (?)
      SQL

      delete_where("notifications", [ "recipient_id IN (?)", user_ids ])
      delete_where("notifications", polymorphic("record", "Comment" => comment_ids, "Like" => like_ids, "Post" => post_ids,
                                                "Post::Repost" => removed_repost_ids, "Post::Devlog" => devlog_ids))
      execute([ "UPDATE notifications SET actor_id = NULL WHERE actor_id IN (?)", user_ids ])
      remove(Comment, comment_ids)
      remove(Like, like_ids)
      delete_where("devlog_versions", [ "devlog_id IN (?)", devlog_ids ])
      delete_where("lookout_sessions", [ "user_id IN (?)", user_ids ])
      execute([ "UPDATE lookout_sessions SET devlog_id = NULL WHERE devlog_id IN (?)", devlog_ids ])
      delete_where("post_views", [ "user_id IN (?) OR post_id IN (?)", user_ids, post_ids ])
      remove(Post::Repost, removed_repost_ids)
      remove(Post, post_ids)
      remove(Post::Devlog, devlog_ids - reviewed_devlog_ids)
      remove(Post::GitCommit, removable("Post::GitCommit"))
      # their ship events, fire events and reviewed devlogs stay, without them
      execute([ "UPDATE posts SET user_id = NULL WHERE user_id IN (?)", user_ids ])
    end

    def erase_owned_records!
      remove_where(Vote::Event, [ "user_id IN (?) OR vote_assignment_id IN (SELECT id FROM vote_assignments WHERE user_id IN (?))", user_ids, user_ids ])
      OWNED.each { |model| remove_where(model, [ "user_id IN (?)", user_ids ]) }
      remove_where(Follow, [ "follower_id IN (?) OR followed_id IN (?)", user_ids, user_ids ])
      remove_where(Vote::ReasonEmbedding, [ "vote_id IN (SELECT id FROM votes WHERE user_id IN (?))", user_ids ])
      remove_where(StickyStreak, [ "user_id IN (?) AND id NOT IN (SELECT sticky_streak_id FROM sticky_streak_claims)", user_ids ])
      delete_where("user_preference", [ "user_id IN (?)", user_ids ])
      delete_where("flipper_gates", [ "value IN (?)", user_ids.map { |id| "User;#{id}" } ])

      participant_ids = select_ids([ "SELECT id FROM raffle_participants WHERE user_id IN (?)", user_ids ])
      winner_ids = select_ids([ <<~SQL, participant_ids, participant_ids ])
        SELECT winner_participant_id FROM raffle_draws WHERE winner_participant_id IN (?)
        UNION SELECT winner_participant_id FROM raffle_weeks WHERE winner_participant_id IN (?)
      SQL
      remove_where(Raffle::WeeklyClaim, [ "participant_id IN (?)", participant_ids - winner_ids ])
      remove_where(Raffle::Referral, [ "participant_id IN (?)", participant_ids - winner_ids ])
      remove(Raffle::Participant, participant_ids - winner_ids)
      scrub(Raffle::Participant, winner_ids)
    end

    def erase_by_email!
      rsvp_ids = select_ids([ "SELECT id FROM rsvps WHERE lower(email) IN (?)", emails ])
      remove_where(Rsvp::Reply, [ "rsvp_id IN (?)", rsvp_ids ])
      remove_where(Rsvp::Game, [ "rsvp_id IN (?)", rsvp_ids ])
      remove(Rsvp, rsvp_ids)
      # commits elsewhere authored with their email stay with other people's projects
      execute([ "UPDATE post_git_commits SET author_email = NULL, author_name = NULL WHERE lower(author_email) IN (?)", emails ])
    end

    def scrub_placeholders!
      scrub(Project, sole_project_ids)
      scrub(Post::ShipEvent, sole_ship_event_ids)
      scrub(Post::Devlog, reviewed_devlog_ids)
      scrub(Vote, select_ids([ "SELECT id FROM votes WHERE user_id IN (?)", user_ids ]))
      scrub(ShopSuggestion, select_ids([ "SELECT id FROM shop_suggestions WHERE user_id IN (?)", user_ids ]))
      { Project => sole_project_ids, Post::Devlog => reviewed_devlog_ids }.each do |model, ids|
        model.unscoped.where(id: ids, deleted_at: nil).update_all(deleted_at: Time.current)
      end
      # other people's reposts of what's left in those projects are hidden, as a project deletion does
      Post::Repost.unscoped.where(deleted_at: nil, original_post_id: Post.where(project_id: sole_project_ids).select(:id)).update_all(deleted_at: Time.current)
    end

    def close_open_work!
      now = Time.current
      ShopOrder.where(user_id: user_ids, aasm_state: OPEN_ORDER_STATES)
               .update_all(aasm_state: "rejected", rejection_reason: CANCELLATION_REASON, internal_rejection_reason: CANCELLATION_REASON, rejected_at: now, updated_at: now)
      ReviewerPayoutRequest.where(user_id: user_ids, aasm_state: "pending").update_all(aasm_state: "rejected", updated_at: now)
      ShopSuggestion.where(user_id: user_ids, aasm_state: "pending").update_all(aasm_state: "rejected", rejection_reason: CANCELLATION_REASON, updated_at: now)
    end

    def anonymize_users!
      execute([ <<~SQL, user_ids ])
        UPDATE users SET email = NULL, guest_email = NULL, hcb_email = NULL, first_name = NULL, last_name = NULL,
          display_name = 'deleted-user-' || id, bio = NULL, slack_id = NULL, ip_address = NULL, user_agent = NULL,
          geocoded_country = NULL, geocoded_lat = NULL, geocoded_lon = NULL, geocoded_subdivision = NULL, timezone = NULL,
          age_attestation = NULL, api_key = NULL, session_token = NULL, ref = NULL, user_ref = NULL, enriched_ref = NULL,
          internal_notes = NULL, banned_reason = NULL, interests = '{}', regions = '{}', granted_roles = '{}', updated_at = now()
        WHERE id IN (?)
      SQL
      # entries made through the API or by a reviewer read "Name (id)"
      user_ids.each do |id|
        execute([ "UPDATE ledger_entries SET created_by = regexp_replace(created_by, ?, ?) WHERE created_by LIKE ?",
                  "^.* \\(#{id}\\)", "Deleted user (#{id})", "% (#{id})%" ])
      end
      # balance adjustments stay as the audit trail of the ledger; they hold amounts and reasons, not personal data
      delete_where("versions", [ "item_type = 'User' AND item_id IN (?) AND event <> 'balance_adjustment'", user_ids.map(&:to_s) ])
      execute([ "UPDATE versions SET whodunnit = NULL WHERE whodunnit IN (?)", user_ids.map(&:to_s) ])
    end

    def recount!
      execute([ <<~SQL, (member_project_ids + removable_posts.filter_map(&:last)).uniq ])
        UPDATE projects SET
          memberships_count = (SELECT count(*) FROM project_memberships WHERE project_memberships.project_id = projects.id),
          devlogs_count = (SELECT count(*) FROM posts WHERE posts.project_id = projects.id AND posts.postable_type = 'Post::Devlog'),
          duration_seconds = (
            SELECT coalesce(sum(post_devlogs.duration_seconds), 0) FROM posts
            JOIN post_devlogs ON post_devlogs.id = posts.postable_id
            WHERE posts.project_id = projects.id AND posts.postable_type = 'Post::Devlog' AND post_devlogs.deleted_at IS NULL
          )
        WHERE id IN (?)
      SQL
      execute([ <<~SQL, @recount_devlog_ids ])
        UPDATE post_devlogs SET
          likes_count = (SELECT count(*) FROM likes WHERE likes.likeable_type = 'Post::Devlog' AND likes.likeable_id = post_devlogs.id),
          comments_count = (SELECT count(*) FROM comments WHERE comments.commentable_type = 'Post::Devlog' AND comments.commentable_id = post_devlogs.id)
        WHERE id IN (?)
      SQL
      execute([ <<~SQL, @recount_post_ids ])
        UPDATE posts SET
          reposts_count = (SELECT count(*) FROM post_reposts WHERE post_reposts.original_post_id = posts.id),
          views_count = (SELECT count(*) FROM post_views WHERE post_views.post_id = posts.id)
        WHERE id IN (?)
      SQL
    end

    # Ahoy lives in its own database when configured, so it can't share the transaction
    def erase_analytics!(dry_run:)
      return if ENV["AHOY_DB_URL"].blank?

      [ Ahoy::Event, Ahoy::Visit ].each do |model|
        scope = model.where(user_id: user_ids)
        @deleted[model.table_name] += dry_run ? scope.count : scope.delete_all
      end
    rescue ActiveRecord::ActiveRecordError => e
      raise DependencyUnavailable, "ahoy: #{e.class}"
    end

    def erase_external!
      @blobs.each(&:delete)
      if SemanticSearch.redis_url.present?
        documents = { "user" => user_ids, "project" => sole_project_ids, "devlog" => devlog_ids, "ship" => sole_ship_event_ids }
        SemanticSearch.redis.del(*documents.flat_map { |type, ids| ids.map { |id| SemanticSearch::Document.redis_key_for(type, id) } })
        SemanticSearch.clear_result_cache
      end
      if Gorse.enabled?
        gorse = Gorse::Client.new
        user_ids.each { |id| gorse.delete_user!("user:#{id}") }
        sole_project_ids.each { |id| gorse.delete_item!("project:#{id}") }
        (removed_post_ids + removed_repost_post_ids).each { |id| gorse.delete_item!("post:#{id}") }
      end
      Rails.cache.delete_multi(user_ids.map { |id| "user/#{id}/sidebar_balance" } + @hackatime_uids.map { |uid| "hackatime_api_key:#{uid}" })
    rescue Aws::Errors::ServiceError, Seahorse::Client::NetworkingError, Redis::BaseError, Faraday::Error, SystemCallError => e
      raise DependencyUnavailable, e.class.name
    end

    # shows up in the admin audit log on the placeholder account; the request id is all it holds
    def record_erasure!(request_id)
      user_ids.each do |id|
        PaperTrail::Version.create!(item_type: "User", item_id: id, event: "privacy_erasure", whodunnit: "Privacy hub", object_changes: { request_id: })
      end
    end

    def emails
      @emails ||= (@subject.emails + User.where(id: user_ids).pluck(:email, :guest_email, :hcb_email).flatten.compact.map(&:downcase)).uniq
    end

    # keeps a placeholder row, minus its personal content and the copies of it in PaperTrail
    def scrub(model, ids)
      return if ids.empty?

      fields = SCRUBBED.fetch(model)
      model.unscoped.where(id: ids).update_all(fields)
      keys = fields.keys.map(&:to_s)
      execute([ "UPDATE versions SET object = object - ARRAY[?]::text[], object_changes = object_changes - ARRAY[?]::text[] WHERE item_type = ? AND item_id IN (?)",
                keys, keys, model.base_class.name, ids.map(&:to_s) ])
    end

    # deletes rows along with their PaperTrail history
    def remove(model, ids)
      return if ids.empty?

      delete_where("versions", [ "item_type = ? AND item_id IN (?)", model.base_class.name, ids.map(&:to_s) ]) if model.try(:paper_trail_options)
      delete_where(model.table_name, [ "id IN (?)", ids ])
    end

    def remove_where(model, condition) = remove(model, select_where("SELECT id FROM #{model.table_name}", condition))
    def delete_where(table, condition) = @deleted[table] += execute([ "DELETE FROM #{table} WHERE #{condition.first}", *condition.drop(1) ])
    def select_where(select, condition) = select_ids([ "#{select} WHERE #{condition.first}", *condition.drop(1) ])

    # matches any {type => ids} pair of a polymorphic association
    def polymorphic(name, records) = [ records.map { "(#{name}_type = ? AND #{name}_id IN (?))" }.join(" OR "), *records.flatten(1) ]

    def select_ids(statement) = connection.select_values(sanitize(statement)).map(&:to_i)
    def execute(statement) = connection.exec_update(sanitize(statement))
    def sanitize(statement) = ActiveRecord::Base.sanitize_sql_array(statement)
    def connection = ActiveRecord::Base.connection
  end
end
