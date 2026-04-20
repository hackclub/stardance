# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_04_20_100123) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

  # Custom types defined in this database.
  # Note that some types may not work with other database engines. Be careful if changing database.
  create_enum "shop_region_type", ["US", "EU", "UK", "IN", "CA", "AU", "XX"]

  create_table "action_mailbox_inbound_emails", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "message_checksum", null: false
    t.string "message_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "message_checksum"], name: "index_action_mailbox_inbound_emails_uniqueness", unique: true
  end

  create_table "active_insights_jobs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.float "db_runtime"
    t.float "duration"
    t.datetime "finished_at"
    t.string "job"
    t.string "queue"
    t.float "queue_time"
    t.datetime "scheduled_at"
    t.datetime "started_at"
    t.datetime "updated_at", null: false
    t.string "uuid"
    t.index ["started_at", "duration", "queue_time"], name: "idx_on_started_at_duration_queue_time_010695b74f"
    t.index ["started_at", "duration"], name: "index_active_insights_jobs_on_started_at_and_duration"
    t.index ["started_at"], name: "index_active_insights_jobs_on_started_at"
  end

  create_table "active_insights_requests", force: :cascade do |t|
    t.string "action"
    t.string "controller"
    t.datetime "created_at", null: false
    t.float "db_runtime"
    t.float "duration"
    t.datetime "finished_at"
    t.string "format"
    t.virtual "formatted_controller", type: :string, as: "(((controller)::text || '#'::text) || (action)::text)", stored: true
    t.string "http_method"
    t.string "ip_address"
    t.text "path"
    t.datetime "started_at"
    t.integer "status"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.string "uuid"
    t.float "view_runtime"
    t.index ["started_at", "duration"], name: "index_active_insights_requests_on_started_at_and_duration"
    t.index ["started_at", "formatted_controller"], name: "idx_on_started_at_formatted_controller_5d659a01d9"
    t.index ["started_at"], name: "index_active_insights_requests_on_started_at"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "blazer_audits", force: :cascade do |t|
    t.datetime "created_at"
    t.string "data_source"
    t.bigint "query_id"
    t.text "statement"
    t.bigint "user_id"
    t.index ["created_at"], name: "index_blazer_audits_on_created_at"
    t.index ["query_id"], name: "index_blazer_audits_on_query_id"
    t.index ["user_id"], name: "index_blazer_audits_on_user_id"
  end

  create_table "blazer_checks", force: :cascade do |t|
    t.string "check_type"
    t.datetime "created_at", null: false
    t.bigint "creator_id"
    t.text "emails"
    t.datetime "last_run_at"
    t.text "message"
    t.bigint "query_id"
    t.string "schedule"
    t.text "slack_channels"
    t.string "state"
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_blazer_checks_on_creator_id"
    t.index ["query_id"], name: "index_blazer_checks_on_query_id"
  end

  create_table "blazer_dashboard_queries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "dashboard_id"
    t.integer "position"
    t.bigint "query_id"
    t.datetime "updated_at", null: false
    t.index ["dashboard_id"], name: "index_blazer_dashboard_queries_on_dashboard_id"
    t.index ["query_id"], name: "index_blazer_dashboard_queries_on_query_id"
  end

  create_table "blazer_dashboards", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "creator_id"
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_blazer_dashboards_on_creator_id"
  end

  create_table "blazer_queries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "creator_id"
    t.string "data_source"
    t.text "description"
    t.string "name"
    t.text "statement"
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_blazer_queries_on_creator_id"
  end

  create_table "comments", force: :cascade do |t|
    t.text "body", null: false
    t.bigint "commentable_id", null: false
    t.string "commentable_type", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["commentable_type", "commentable_id", "created_at"], name: "index_comments_on_commentable_and_created_at"
    t.index ["commentable_type", "commentable_id"], name: "index_comments_on_commentable"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "devlog_versions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "devlog_id", null: false
    t.text "reverse_diff", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "version_number", null: false
    t.index ["devlog_id", "version_number"], name: "index_devlog_versions_on_devlog_id_and_version_number", unique: true
    t.index ["devlog_id"], name: "index_devlog_versions_on_devlog_id"
    t.index ["user_id"], name: "index_devlog_versions_on_user_id"
  end

  create_table "disco_recommendations", force: :cascade do |t|
    t.string "context"
    t.datetime "created_at", null: false
    t.bigint "item_id"
    t.string "item_type"
    t.float "score"
    t.bigint "subject_id"
    t.string "subject_type"
    t.datetime "updated_at", null: false
    t.index ["item_type", "item_id"], name: "index_disco_recommendations_on_item"
    t.index ["subject_type", "subject_id"], name: "index_disco_recommendations_on_subject"
  end

  create_table "extension_usages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "project_id", null: false
    t.datetime "recorded_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["project_id", "recorded_at"], name: "index_extension_usages_on_project_id_and_recorded_at"
    t.index ["project_id"], name: "index_extension_usages_on_project_id"
    t.index ["recorded_at"], name: "index_extension_usages_on_recorded_at"
    t.index ["user_id"], name: "index_extension_usages_on_user_id"
  end

  create_table "flavortime_sessions", force: :cascade do |t|
    t.string "app_version"
    t.datetime "created_at", null: false
    t.integer "discord_shared_seconds", default: 0, null: false
    t.integer "discord_status_seconds", default: 0, null: false
    t.datetime "ended_at"
    t.string "ended_reason"
    t.datetime "expires_at", null: false
    t.datetime "last_heartbeat_at", null: false
    t.string "platform"
    t.string "session_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["expires_at"], name: "index_flavortime_sessions_on_expires_at"
    t.index ["session_id"], name: "index_flavortime_sessions_on_session_id", unique: true
    t.index ["user_id", "created_at"], name: "index_flavortime_sessions_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_flavortime_sessions_on_user_id"
  end

  create_table "flipper_features", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_flipper_features_on_key", unique: true
  end

  create_table "flipper_gates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "feature_key", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["feature_key", "key", "value"], name: "index_flipper_gates_on_feature_key_and_key_and_value", unique: true
  end

  create_table "fulfillment_payout_lines", force: :cascade do |t|
    t.integer "amount"
    t.datetime "created_at", null: false
    t.bigint "fulfillment_payout_run_id", null: false
    t.integer "order_count"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["fulfillment_payout_run_id"], name: "index_fulfillment_payout_lines_on_fulfillment_payout_run_id"
    t.index ["user_id"], name: "index_fulfillment_payout_lines_on_user_id"
  end

  create_table "fulfillment_payout_runs", force: :cascade do |t|
    t.string "aasm_state"
    t.datetime "approved_at"
    t.bigint "approved_by_user_id"
    t.datetime "created_at", null: false
    t.datetime "period_end"
    t.datetime "period_start"
    t.integer "total_amount"
    t.integer "total_orders"
    t.datetime "updated_at", null: false
  end

  create_table "funnel_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "event_name", null: false
    t.jsonb "properties", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["created_at"], name: "index_funnel_events_on_created_at"
    t.index ["email"], name: "index_funnel_events_on_email"
    t.index ["event_name", "created_at"], name: "index_funnel_events_on_event_name_and_created_at"
    t.index ["event_name"], name: "index_funnel_events_on_event_name"
    t.index ["user_id"], name: "index_funnel_events_on_user_id"
  end

  create_table "hackatime_time_loss_audits", force: :cascade do |t|
    t.datetime "audited_at", null: false
    t.datetime "created_at", null: false
    t.integer "devlog_total_seconds", default: 0, null: false
    t.integer "difference_seconds", default: 0, null: false
    t.text "hackatime_keys", default: "", null: false
    t.integer "per_project_sum_seconds", default: 0, null: false
    t.bigint "project_id", null: false
    t.integer "ungrouped_total_seconds", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["audited_at"], name: "index_hackatime_time_loss_audits_on_audited_at"
    t.index ["difference_seconds"], name: "index_hackatime_time_loss_audits_on_difference_seconds"
    t.index ["project_id"], name: "index_hackatime_time_loss_audits_on_project_id"
    t.index ["user_id"], name: "index_hackatime_time_loss_audits_on_user_id"
  end

  create_table "hcb_credentials", force: :cascade do |t|
    t.text "access_token_ciphertext"
    t.string "base_url"
    t.string "client_id"
    t.text "client_secret_ciphertext"
    t.datetime "created_at", null: false
    t.string "redirect_uri"
    t.text "refresh_token_ciphertext"
    t.string "slug"
    t.datetime "updated_at", null: false
  end

  create_table "ledger_entries", force: :cascade do |t|
    t.integer "amount"
    t.datetime "created_at", null: false
    t.string "created_by"
    t.bigint "ledgerable_id", null: false
    t.string "ledgerable_type", null: false
    t.string "reason"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["ledgerable_type", "ledgerable_id"], name: "index_ledger_entries_on_ledgerable"
    t.index ["user_id"], name: "index_ledger_entries_on_user_id"
  end

  create_table "likes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "likeable_id", null: false
    t.string "likeable_type", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["likeable_type", "likeable_id"], name: "index_likes_on_likeable"
    t.index ["user_id", "likeable_type", "likeable_id"], name: "index_likes_on_user_id_and_likeable_type_and_likeable_id", unique: true
    t.index ["user_id"], name: "index_likes_on_user_id"
  end

  create_table "messages", force: :cascade do |t|
    t.string "block_path"
    t.string "content"
    t.datetime "created_at", null: false
    t.bigint "sent_by_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["sent_by_id"], name: "index_messages_on_sent_by_id"
    t.index ["user_id"], name: "index_messages_on_user_id"
  end

  create_table "post_devlogs", force: :cascade do |t|
    t.string "body"
    t.integer "comments_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.integer "duration_seconds"
    t.text "hackatime_projects_key_snapshot"
    t.datetime "hackatime_pulled_at"
    t.boolean "lapse_video_processing", default: false, null: false
    t.integer "likes_count", default: 0, null: false
    t.datetime "synced_at"
    t.boolean "tutorial", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_post_devlogs_on_deleted_at"
  end

  create_table "post_fire_events", force: :cascade do |t|
    t.string "body"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "post_git_commits", force: :cascade do |t|
    t.integer "additions", default: 0
    t.string "author_email"
    t.string "author_name"
    t.datetime "authored_at"
    t.datetime "created_at", null: false
    t.integer "deletions", default: 0
    t.integer "files_changed", default: 0
    t.text "message"
    t.string "sha", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["sha"], name: "index_post_git_commits_on_sha", unique: true
  end

  create_table "post_ship_events", force: :cascade do |t|
    t.float "base_hours"
    t.string "body"
    t.boolean "bridge", default: false, null: false
    t.string "certification_status", default: "pending"
    t.datetime "created_at", null: false
    t.text "feedback_reason"
    t.string "feedback_video_url"
    t.float "hours"
    t.float "legacy_payout_deduction"
    t.float "multiplier"
    t.decimal "originality_median", precision: 5, scale: 2
    t.decimal "originality_percentile", precision: 5, scale: 2
    t.decimal "overall_percentile", precision: 5, scale: 2
    t.decimal "overall_score", precision: 5, scale: 2
    t.float "payout"
    t.datetime "payout_basis_locked_at"
    t.decimal "payout_basis_overall_score", precision: 5, scale: 2
    t.decimal "payout_basis_percentile", precision: 5, scale: 2
    t.string "payout_blessing"
    t.string "payout_curve_version"
    t.text "review_instructions"
    t.decimal "storytelling_median", precision: 5, scale: 2
    t.decimal "storytelling_percentile", precision: 5, scale: 2
    t.datetime "synced_at"
    t.decimal "technical_median", precision: 5, scale: 2
    t.decimal "technical_percentile", precision: 5, scale: 2
    t.datetime "updated_at", null: false
    t.decimal "usability_median", precision: 5, scale: 2
    t.decimal "usability_percentile", precision: 5, scale: 2
    t.integer "votes_count", default: 0, null: false
    t.integer "voting_scale_version", default: 2, null: false
  end

  create_table "posts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "postable_id"
    t.string "postable_type"
    t.bigint "project_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["postable_type", "postable_id"], name: "index_posts_on_postable_type_and_postable_id", unique: true
    t.index ["project_id"], name: "index_posts_on_project_id"
    t.index ["user_id"], name: "index_posts_on_user_id"
  end

  create_table "project_follows", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "project_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["project_id"], name: "index_project_follows_on_project_id"
    t.index ["user_id", "project_id"], name: "index_project_follows_on_user_id_and_project_id", unique: true
    t.index ["user_id"], name: "index_project_follows_on_user_id"
  end

  create_table "project_ideas", force: :cascade do |t|
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.string "model", null: false
    t.text "prompt", null: false
    t.datetime "updated_at", null: false
  end

  create_table "project_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "project_id", null: false
    t.integer "role"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["project_id", "user_id"], name: "index_project_memberships_on_project_id_and_user_id", unique: true
    t.index ["project_id"], name: "index_project_memberships_on_project_id"
    t.index ["user_id"], name: "index_project_memberships_on_user_id"
  end

  create_table "project_reports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "details", null: false
    t.bigint "project_id", null: false
    t.string "reason", null: false
    t.bigint "reporter_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_project_reports_on_project_id"
    t.index ["reporter_id", "project_id"], name: "index_project_reports_on_reporter_id_and_project_id", unique: true
    t.index ["reporter_id"], name: "index_project_reports_on_reporter_id"
    t.index ["status", "created_at"], name: "idx_project_reports_status_created_at_desc", order: { created_at: :desc }
  end

  create_table "project_skips", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "project_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["project_id"], name: "index_project_skips_on_project_id"
    t.index ["user_id", "project_id"], name: "index_project_skips_on_user_id_and_project_id", unique: true
    t.index ["user_id"], name: "index_project_skips_on_user_id"
  end

  create_table "projects", force: :cascade do |t|
    t.text "ai_declaration"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "demo_url"
    t.text "description"
    t.integer "devlogs_count", default: 0, null: false
    t.integer "duration_seconds", default: 0, null: false
    t.string "fire_letter_id"
    t.datetime "marked_fire_at"
    t.bigint "marked_fire_by_id"
    t.integer "memberships_count", default: 0, null: false
    t.string "project_categories", default: [], array: true
    t.string "project_type"
    t.text "readme_url"
    t.text "repo_url"
    t.boolean "shadow_banned", default: false, null: false
    t.datetime "shadow_banned_at"
    t.text "shadow_banned_reason"
    t.string "ship_status", default: "draft"
    t.datetime "shipped_at"
    t.datetime "synced_at"
    t.string "title", null: false
    t.boolean "tutorial", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_projects_on_deleted_at"
    t.index ["marked_fire_by_id"], name: "index_projects_on_marked_fire_by_id"
    t.index ["shadow_banned"], name: "index_projects_on_shadow_banned"
  end

  create_table "report_review_tokens", force: :cascade do |t|
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "report_id", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.datetime "used_at"
    t.index ["report_id", "action"], name: "index_report_review_tokens_on_report_id_and_action", unique: true
    t.index ["report_id"], name: "index_report_review_tokens_on_report_id"
    t.index ["token"], name: "index_report_review_tokens_on_token", unique: true
  end

  create_table "rsvp_games", force: :cascade do |t|
    t.string "board", default: "---------", null: false
    t.datetime "created_at", null: false
    t.integer "move_count", default: 0, null: false
    t.bigint "rsvp_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["rsvp_id", "status"], name: "index_rsvp_games_on_rsvp_id_and_status"
    t.index ["rsvp_id"], name: "index_rsvp_games_on_rsvp_id"
  end

  create_table "rsvp_replies", force: :cascade do |t|
    t.text "body_html"
    t.text "body_text"
    t.datetime "created_at", null: false
    t.string "message_id"
    t.datetime "received_at"
    t.bigint "rsvp_id", null: false
    t.string "subject"
    t.datetime "updated_at", null: false
    t.index ["message_id"], name: "index_rsvp_replies_on_message_id", unique: true
    t.index ["rsvp_id"], name: "index_rsvp_replies_on_rsvp_id"
  end

  create_table "rsvps", force: :cascade do |t|
    t.datetime "click_confirmed_at"
    t.string "confirmation_token"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "ip_address"
    t.string "ref"
    t.datetime "reply_confirmed_at"
    t.datetime "signup_confirmation_sent_at"
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.index ["confirmation_token"], name: "index_rsvps_on_confirmation_token", unique: true
  end

  create_table "shop_card_grants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "expected_amount_cents"
    t.string "hcb_grant_hashid"
    t.bigint "shop_item_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["shop_item_id"], name: "index_shop_card_grants_on_shop_item_id"
    t.index ["user_id"], name: "index_shop_card_grants_on_user_id"
  end

  create_table "shop_items", force: :cascade do |t|
    t.string "accessory_tag"
    t.jsonb "agh_contents"
    t.bigint "attached_shop_item_ids", default: [], array: true
    t.string "blocked_countries", default: [], array: true
    t.boolean "buyable_by_self", default: true
    t.datetime "created_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.bigint "created_by_user_id"
    t.bigint "default_assigned_user_id"
    t.bigint "default_assigned_user_id_au"
    t.bigint "default_assigned_user_id_ca"
    t.bigint "default_assigned_user_id_eu"
    t.bigint "default_assigned_user_id_in"
    t.bigint "default_assigned_user_id_uk"
    t.bigint "default_assigned_user_id_us"
    t.bigint "default_assigned_user_id_xx"
    t.string "description"
    t.boolean "draft", default: false, null: false
    t.boolean "enabled"
    t.boolean "enabled_au"
    t.boolean "enabled_ca"
    t.boolean "enabled_eu"
    t.boolean "enabled_in"
    t.boolean "enabled_uk"
    t.datetime "enabled_until"
    t.boolean "enabled_us"
    t.boolean "enabled_xx"
    t.integer "hacker_score"
    t.string "hcb_category_lock"
    t.string "hcb_keyword_lock"
    t.string "hcb_merchant_lock"
    t.boolean "hcb_one_time_use", default: false
    t.text "hcb_preauthorization_instructions"
    t.string "internal_description"
    t.boolean "limited"
    t.text "long_description"
    t.integer "max_qty"
    t.string "name"
    t.integer "old_prices", default: [], array: true
    t.boolean "one_per_person_ever"
    t.integer "past_purchases", default: 0
    t.integer "payout_percentage", default: 0
    t.integer "required_ships_count", default: 1
    t.date "required_ships_end_date"
    t.date "required_ships_start_date"
    t.string "requires_achievement", default: [], array: true
    t.boolean "requires_ship", default: false
    t.boolean "requires_verification_call", default: false, null: false
    t.integer "sale_percentage"
    t.boolean "show_image_in_shop", default: false
    t.boolean "show_in_carousel"
    t.integer "site_action"
    t.string "source_region"
    t.boolean "special"
    t.integer "stock"
    t.integer "ticket_cost"
    t.string "type"
    t.boolean "unlisted", default: false
    t.date "unlock_on"
    t.datetime "updated_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.decimal "usd_cost"
    t.decimal "usd_offset_au", precision: 10, scale: 2
    t.decimal "usd_offset_ca", precision: 10, scale: 2
    t.decimal "usd_offset_eu", precision: 10, scale: 2
    t.decimal "usd_offset_in", precision: 10, scale: 2
    t.decimal "usd_offset_uk", precision: 10, scale: 2
    t.decimal "usd_offset_us", precision: 10, scale: 2
    t.decimal "usd_offset_xx", precision: 10, scale: 2
    t.bigint "user_id"
    t.index ["created_by_user_id"], name: "index_shop_items_on_created_by_user_id"
    t.index ["default_assigned_user_id"], name: "index_shop_items_on_default_assigned_user_id"
    t.index ["user_id"], name: "index_shop_items_on_user_id"
  end

  create_table "shop_order_reviews", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "reason", null: false
    t.bigint "shop_order_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "verdict", null: false
    t.index ["shop_order_id", "user_id"], name: "index_shop_order_reviews_on_shop_order_id_and_user_id", unique: true
    t.index ["shop_order_id"], name: "index_shop_order_reviews_on_shop_order_id"
    t.index ["user_id"], name: "index_shop_order_reviews_on_user_id"
  end

  create_table "shop_orders", force: :cascade do |t|
    t.string "aasm_state"
    t.bigint "accessory_ids", default: [], array: true
    t.bigint "assigned_to_user_id"
    t.datetime "awaiting_periodical_fulfillment_at"
    t.datetime "created_at", null: false
    t.string "external_ref"
    t.bigint "fraud_related_project_id"
    t.text "frozen_address_ciphertext"
    t.decimal "frozen_item_price", precision: 6, scale: 2
    t.datetime "fulfilled_at"
    t.string "fulfilled_by"
    t.decimal "fulfillment_cost", precision: 6, scale: 2
    t.bigint "fulfillment_payout_line_id"
    t.text "internal_notes"
    t.text "internal_rejection_reason"
    t.string "joe_case_url"
    t.datetime "on_hold_at"
    t.bigint "parent_order_id"
    t.integer "quantity"
    t.string "region", limit: 2
    t.datetime "rejected_at"
    t.string "rejection_reason"
    t.bigint "shop_card_grant_id"
    t.bigint "shop_item_id", null: false
    t.string "tracking_number"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "warehouse_package_id"
    t.index ["aasm_state", "created_at"], name: "idx_shop_orders_aasm_state_created_at_desc", order: { created_at: :desc }
    t.index ["assigned_to_user_id"], name: "index_shop_orders_on_assigned_to_user_id"
    t.index ["fulfillment_payout_line_id"], name: "index_shop_orders_on_fulfillment_payout_line_id"
    t.index ["parent_order_id"], name: "index_shop_orders_on_parent_order_id"
    t.index ["region"], name: "index_shop_orders_on_region"
    t.index ["shop_card_grant_id"], name: "index_shop_orders_on_shop_card_grant_id"
    t.index ["shop_item_id", "aasm_state", "quantity"], name: "idx_shop_orders_item_state_qty"
    t.index ["shop_item_id", "aasm_state"], name: "idx_shop_orders_stock_calc"
    t.index ["shop_item_id"], name: "index_shop_orders_on_shop_item_id"
    t.index ["user_id", "shop_item_id", "aasm_state"], name: "idx_shop_orders_user_item_state"
    t.index ["user_id", "shop_item_id"], name: "idx_shop_orders_user_item_unique"
    t.index ["user_id"], name: "index_shop_orders_on_user_id"
    t.index ["warehouse_package_id"], name: "index_shop_orders_on_warehouse_package_id"
  end

  create_table "shop_suggestions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "explanation"
    t.text "item"
    t.string "link"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_shop_suggestions_on_user_id"
  end

  create_table "shop_warehouse_packages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "frozen_address_ciphertext"
    t.jsonb "frozen_contents"
    t.string "theseus_package_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["theseus_package_id"], name: "index_shop_warehouse_packages_on_theseus_package_id", unique: true
    t.index ["user_id"], name: "index_shop_warehouse_packages_on_user_id"
  end

  create_table "show_and_tell_attendances", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date"
    t.boolean "give_presentation_payout", default: false, null: false
    t.boolean "payout_given", default: false, null: false
    t.datetime "payout_given_at"
    t.bigint "payout_given_by_id"
    t.bigint "project_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.boolean "winner", default: false, null: false
    t.boolean "winner_payout_given", default: false, null: false
    t.index ["payout_given_by_id"], name: "index_show_and_tell_attendances_on_payout_given_by_id"
    t.index ["project_id"], name: "index_show_and_tell_attendances_on_project_id"
    t.index ["user_id"], name: "index_show_and_tell_attendances_on_user_id"
  end

  create_table "show_and_tell_payout_records", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.text "notes"
    t.bigint "payout_given_by_id", null: false
    t.datetime "updated_at", null: false
    t.index ["date"], name: "index_show_and_tell_payout_records_on_date", unique: true
    t.index ["payout_given_by_id"], name: "index_show_and_tell_payout_records_on_payout_given_by_id"
  end

  create_table "sidequest_entries", force: :cascade do |t|
    t.string "aasm_state", default: "pending", null: false
    t.datetime "created_at", null: false
    t.boolean "is_rejection_fee_charged", default: false, null: false
    t.bigint "project_id", null: false
    t.text "rejection_message"
    t.datetime "reviewed_at"
    t.bigint "reviewed_by_id"
    t.bigint "sidequest_id", null: false
    t.datetime "updated_at", null: false
    t.index ["aasm_state"], name: "index_sidequest_entries_on_aasm_state"
    t.index ["project_id"], name: "index_sidequest_entries_on_project_id"
    t.index ["reviewed_by_id"], name: "index_sidequest_entries_on_reviewed_by_id"
    t.index ["sidequest_id"], name: "index_sidequest_entries_on_sidequest_id"
  end

  create_table "sidequests", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description"
    t.datetime "expires_at"
    t.string "external_page_link"
    t.string "slug", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_sidequests_on_slug", unique: true
  end

  create_table "support_vibes", force: :cascade do |t|
    t.jsonb "concern_message_links"
    t.jsonb "concern_messages"
    t.jsonb "concerns", default: []
    t.datetime "created_at", null: false
    t.jsonb "notable_quotes", default: []
    t.decimal "overall_sentiment", precision: 3, scale: 2
    t.datetime "period_end"
    t.datetime "period_start"
    t.string "rating"
    t.jsonb "unresolved_queries", default: {}
    t.datetime "updated_at", null: false
    t.index ["period_start"], name: "index_support_vibes_on_period_start"
  end

  create_table "user_achievements", force: :cascade do |t|
    t.string "achievement_slug", null: false
    t.datetime "created_at", null: false
    t.datetime "earned_at", null: false
    t.boolean "notified", default: false, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "achievement_slug"], name: "index_user_achievements_on_user_id_and_achievement_slug", unique: true
    t.index ["user_id"], name: "index_user_achievements_on_user_id"
  end

  create_table "user_hackatime_projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "project_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["project_id"], name: "index_user_hackatime_projects_on_project_id"
    t.index ["user_id", "name"], name: "index_user_hackatime_projects_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_user_hackatime_projects_on_user_id"
  end

  create_table "user_identities", force: :cascade do |t|
    t.string "access_token_bidx"
    t.text "access_token_ciphertext"
    t.datetime "created_at", null: false
    t.string "provider"
    t.string "refresh_token_bidx"
    t.text "refresh_token_ciphertext"
    t.string "uid"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["access_token_bidx"], name: "index_user_identities_on_access_token_bidx"
    t.index ["provider", "uid"], name: "index_user_identities_on_provider_and_uid", unique: true
    t.index ["refresh_token_bidx"], name: "index_user_identities_on_refresh_token_bidx"
    t.index ["user_id", "provider"], name: "index_user_identities_on_user_id_and_provider", unique: true
    t.index ["user_id"], name: "index_user_identities_on_user_id"
  end

  create_table "user_vote_verdicts", force: :cascade do |t|
    t.datetime "assessed_at"
    t.datetime "created_at", null: false
    t.float "quality_score"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "verdict", default: "neutral", null: false
    t.index ["user_id"], name: "index_user_vote_verdicts_on_user_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "airtable_record_id"
    t.string "api_key"
    t.boolean "banned", default: false, null: false
    t.datetime "banned_at"
    t.text "banned_reason"
    t.string "club_link"
    t.string "club_name"
    t.integer "cookie_clicks", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "email"
    t.string "enriched_ref"
    t.string "first_name"
    t.integer "flavortown_message_count_14d"
    t.integer "flavortown_support_message_count_14d"
    t.string "granted_roles", default: [], null: false, array: true
    t.boolean "has_gotten_free_stickers", default: false
    t.boolean "has_pending_achievements", default: false, null: false
    t.string "hcb_email"
    t.text "internal_notes"
    t.string "last_name"
    t.boolean "leaderboard_optin", default: false, null: false
    t.boolean "manual_ysws_override"
    t.datetime "metrics_synced_at"
    t.integer "projects_count"
    t.integer "projects_shipped_count"
    t.string "ref"
    t.string "regions", default: [], array: true
    t.boolean "search_engine_indexing_off", default: false, null: false
    t.boolean "send_notifications_for_followed_devlogs", default: true, null: false
    t.boolean "send_notifications_for_new_comments", default: true, null: false
    t.boolean "send_notifications_for_new_followers", default: true, null: false
    t.boolean "send_votes_to_slack", default: false, null: false
    t.string "session_token"
    t.boolean "shadow_banned", default: false, null: false
    t.datetime "shadow_banned_at"
    t.text "shadow_banned_reason"
    t.enum "shop_region", enum_type: "shop_region_type"
    t.boolean "slack_balance_notifications", default: false, null: false
    t.string "slack_id"
    t.datetime "slack_messages_updated_at"
    t.boolean "special_effects_enabled", default: true, null: false
    t.datetime "synced_at"
    t.string "things_dismissed", default: [], null: false, array: true
    t.string "tutorial_steps_completed", default: [], array: true
    t.datetime "updated_at", null: false
    t.string "verification_status", default: "needs_submission", null: false
    t.boolean "vote_anonymously", default: false, null: false
    t.integer "vote_balance", default: 0, null: false
    t.integer "votes_count"
    t.boolean "voting_locked", default: false, null: false
    t.boolean "ysws_eligible", default: false, null: false
    t.index ["airtable_record_id"], name: "index_users_on_airtable_record_id", unique: true
    t.index ["api_key"], name: "index_users_on_api_key", unique: true
    t.index ["email"], name: "index_users_on_email"
    t.index ["session_token"], name: "index_users_on_session_token", unique: true
    t.index ["slack_id"], name: "index_users_on_slack_id", unique: true
  end

  create_table "versions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at"
    t.string "event", null: false
    t.string "item_id", null: false
    t.string "item_type", null: false
    t.jsonb "object", default: {}
    t.jsonb "object_changes", default: {}
    t.string "whodunnit"
    t.index ["item_id", "created_at"], name: "idx_versions_project_report_status", where: "(((item_type)::text = 'Project::Report'::text) AND (object_changes ? 'status'::text))"
    t.index ["item_id", "created_at"], name: "idx_versions_shop_order_aasm_state", where: "(((item_type)::text = 'ShopOrder'::text) AND (object_changes ? 'aasm_state'::text))"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
    t.index ["object"], name: "index_versions_on_object", using: :gin
    t.index ["object_changes"], name: "index_versions_on_object_changes", using: :gin
  end

  create_table "vote_reason_embeddings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.vector "embedding", limit: 1536, null: false
    t.string "model_version", default: "text-embedding-3-small", null: false
    t.datetime "updated_at", null: false
    t.bigint "vote_id", null: false
    t.index ["vote_id"], name: "index_vote_reason_embeddings_on_vote_id", unique: true
  end

  create_table "votes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "demo_url_clicked", default: false
    t.integer "originality_score"
    t.bigint "project_id", null: false
    t.text "reason"
    t.string "reason_quality_label"
    t.float "reason_quality_score"
    t.boolean "repo_url_clicked", default: false
    t.bigint "ship_event_id", null: false
    t.integer "storytelling_score"
    t.boolean "suspicious", default: false, null: false
    t.integer "technical_score"
    t.integer "time_taken_to_vote"
    t.datetime "updated_at", null: false
    t.integer "usability_score"
    t.bigint "user_id", null: false
    t.string "verdict"
    t.index ["project_id"], name: "index_votes_on_project_id"
    t.index ["reason_quality_label"], name: "index_votes_on_reason_quality_label"
    t.index ["ship_event_id"], name: "index_votes_on_ship_event_id"
    t.index ["suspicious", "created_at"], name: "index_votes_on_suspicious_and_created_at"
    t.index ["user_id", "ship_event_id"], name: "index_votes_on_user_id_and_ship_event_id", unique: true
    t.index ["user_id"], name: "index_votes_on_user_id"
    t.index ["verdict"], name: "index_votes_on_verdict"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "comments", "users"
  add_foreign_key "devlog_versions", "post_devlogs", column: "devlog_id"
  add_foreign_key "devlog_versions", "users"
  add_foreign_key "extension_usages", "projects"
  add_foreign_key "extension_usages", "users"
  add_foreign_key "flavortime_sessions", "users"
  add_foreign_key "fulfillment_payout_lines", "fulfillment_payout_runs"
  add_foreign_key "fulfillment_payout_lines", "users"
  add_foreign_key "fulfillment_payout_runs", "users", column: "approved_by_user_id"
  add_foreign_key "hackatime_time_loss_audits", "projects"
  add_foreign_key "hackatime_time_loss_audits", "users"
  add_foreign_key "ledger_entries", "users"
  add_foreign_key "likes", "users"
  add_foreign_key "messages", "users"
  add_foreign_key "messages", "users", column: "sent_by_id"
  add_foreign_key "posts", "projects"
  add_foreign_key "posts", "users"
  add_foreign_key "project_follows", "projects"
  add_foreign_key "project_follows", "users"
  add_foreign_key "project_memberships", "projects"
  add_foreign_key "project_memberships", "users"
  add_foreign_key "project_reports", "projects"
  add_foreign_key "project_reports", "users", column: "reporter_id"
  add_foreign_key "project_skips", "projects"
  add_foreign_key "project_skips", "users"
  add_foreign_key "projects", "users", column: "marked_fire_by_id"
  add_foreign_key "report_review_tokens", "project_reports", column: "report_id"
  add_foreign_key "rsvp_games", "rsvps"
  add_foreign_key "rsvp_replies", "rsvps"
  add_foreign_key "shop_card_grants", "shop_items"
  add_foreign_key "shop_card_grants", "users"
  add_foreign_key "shop_items", "users"
  add_foreign_key "shop_items", "users", column: "created_by_user_id", on_delete: :nullify, validate: false
  add_foreign_key "shop_items", "users", column: "default_assigned_user_id", on_delete: :nullify
  add_foreign_key "shop_order_reviews", "shop_orders"
  add_foreign_key "shop_order_reviews", "users"
  add_foreign_key "shop_orders", "fulfillment_payout_lines"
  add_foreign_key "shop_orders", "shop_items"
  add_foreign_key "shop_orders", "shop_orders", column: "parent_order_id"
  add_foreign_key "shop_orders", "shop_warehouse_packages", column: "warehouse_package_id"
  add_foreign_key "shop_orders", "users"
  add_foreign_key "shop_orders", "users", column: "assigned_to_user_id", on_delete: :nullify
  add_foreign_key "shop_suggestions", "users"
  add_foreign_key "shop_warehouse_packages", "users"
  add_foreign_key "show_and_tell_attendances", "projects"
  add_foreign_key "show_and_tell_attendances", "users"
  add_foreign_key "show_and_tell_attendances", "users", column: "payout_given_by_id"
  add_foreign_key "show_and_tell_payout_records", "users", column: "payout_given_by_id"
  add_foreign_key "sidequest_entries", "projects"
  add_foreign_key "sidequest_entries", "sidequests"
  add_foreign_key "sidequest_entries", "users", column: "reviewed_by_id"
  add_foreign_key "user_achievements", "users"
  add_foreign_key "user_hackatime_projects", "projects"
  add_foreign_key "user_hackatime_projects", "users"
  add_foreign_key "user_identities", "users"
  add_foreign_key "user_vote_verdicts", "users"
  add_foreign_key "votes", "post_ship_events", column: "ship_event_id"
  add_foreign_key "votes", "projects"
  add_foreign_key "votes", "users"
end
