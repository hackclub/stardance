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

ActiveRecord::Schema[8.1].define(version: 2026_07_22_150605) do
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

  create_table "certificates", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.float "hours_at_issue", null: false
    t.string "name", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["code"], name: "index_certificates_on_code", unique: true
    t.index ["user_id"], name: "index_certificates_on_user_id", unique: true
  end

  create_table "certification_devlog_reviews", force: :cascade do |t|
    t.integer "approved_minutes"
    t.datetime "created_at", null: false
    t.text "justification"
    t.integer "original_minutes"
    t.bigint "post_devlog_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "ysws_review_id", null: false
    t.index ["post_devlog_id"], name: "index_certification_devlog_reviews_on_post_devlog_id"
    t.index ["ysws_review_id"], name: "index_certification_devlog_reviews_on_ysws_review_id"
  end

  create_table "certification_funding_requests", force: :cascade do |t|
    t.integer "approved_amount_cents"
    t.datetime "claim_expires_at"
    t.datetime "claimed_at"
    t.integer "complexity_tier", null: false
    t.datetime "created_at", null: false
    t.datetime "decided_at"
    t.integer "discount_stardust_awarded"
    t.text "feedback"
    t.string "hcb_grant_hashid"
    t.text "internal_reason"
    t.integer "lock_version", default: 0, null: false
    t.bigint "project_id", null: false
    t.integer "requested_amount_cents", null: false
    t.bigint "reviewer_id"
    t.integer "stardust_earned"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["decided_at"], name: "index_certification_funding_requests_on_decided_at"
    t.index ["project_id"], name: "index_certification_funding_requests_on_project_id"
    t.index ["project_id"], name: "index_funding_requests_unique_pending_project", unique: true, where: "(status = 0)"
    t.index ["reviewer_id"], name: "index_certification_funding_requests_on_reviewer_id"
    t.index ["status", "claim_expires_at"], name: "idx_funding_requests_on_status_claim_expires"
    t.index ["user_id"], name: "index_certification_funding_requests_on_user_id"
  end

  create_table "certification_integrities", force: :cascade do |t|
    t.datetime "claimed_at"
    t.bigint "claimed_by_id"
    t.datetime "created_at", null: false
    t.text "decision_justification"
    t.integer "deduction_minutes"
    t.integer "flags", default: 0, null: false
    t.jsonb "fraud_detection_data"
    t.datetime "reviewed_at"
    t.bigint "reviewer_id"
    t.bigint "ship_event_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["claimed_by_id"], name: "index_certification_integrities_on_claimed_by_id"
    t.index ["reviewer_id"], name: "index_certification_integrities_on_reviewer_id"
    t.index ["ship_event_id"], name: "index_certification_integrities_on_ship_event_id", unique: true
    t.index ["status"], name: "index_certification_integrities_on_status"
  end

  create_table "certification_ship_reviews", force: :cascade do |t|
    t.datetime "claim_expires_at"
    t.datetime "claimed_at"
    t.datetime "created_at", null: false
    t.datetime "decided_at"
    t.string "external_certification_id"
    t.text "feedback"
    t.text "internal_reason"
    t.integer "lock_version", default: 0, null: false
    t.bigint "post_ship_event_id"
    t.bigint "project_id", null: false
    t.string "proof_video_url"
    t.text "recert_reason"
    t.bigint "returned_by_id"
    t.bigint "reviewer_id"
    t.float "stardust_earned"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["decided_at"], name: "index_certification_ship_reviews_on_decided_at"
    t.index ["external_certification_id"], name: "index_certification_ship_reviews_on_external_certification_id", unique: true
    t.index ["post_ship_event_id"], name: "index_certification_ship_reviews_on_post_ship_event_id"
    t.index ["project_id"], name: "index_ship_reviews_unique_pending_project", unique: true, where: "(status = 0)"
    t.index ["reviewer_id"], name: "index_certification_ship_reviews_on_reviewer_id"
    t.index ["status", "claim_expires_at"], name: "idx_on_status_claim_expires_at_c7a5e87a52"
  end

  create_table "certification_ysws_reviews", force: :cascade do |t|
    t.datetime "airtable_synced_at", precision: nil
    t.integer "approved_minutes"
    t.datetime "claimed_at"
    t.bigint "claimed_by_id"
    t.datetime "created_at", null: false
    t.datetime "demo_checked_at", precision: nil
    t.string "in_unified_db"
    t.integer "original_minutes"
    t.bigint "post_ship_event_id", null: false
    t.bigint "project_id", null: false
    t.datetime "repo_checked_at", precision: nil
    t.datetime "returned_at"
    t.datetime "reviewed_at", precision: nil
    t.bigint "reviewer_id"
    t.bigint "ship_cert_id"
    t.datetime "spotchecked_at", precision: nil
    t.bigint "spotchecked_by_id"
    t.text "summary_justification"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["claimed_by_id"], name: "index_certification_ysws_reviews_on_claimed_by_id"
    t.index ["post_ship_event_id"], name: "index_certification_ysws_reviews_on_post_ship_event_id"
    t.index ["project_id"], name: "index_certification_ysws_reviews_on_project_id"
    t.index ["reviewer_id"], name: "index_certification_ysws_reviews_on_reviewer_id"
    t.index ["ship_cert_id"], name: "index_certification_ysws_reviews_on_ship_cert_id"
    t.index ["spotchecked_by_id"], name: "index_certification_ysws_reviews_on_spotchecked_by_id"
    t.index ["user_id"], name: "index_certification_ysws_reviews_on_user_id"
  end

  create_table "comments", force: :cascade do |t|
    t.text "body", null: false
    t.bigint "commentable_id", null: false
    t.string "commentable_type", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["commentable_type", "commentable_id", "created_at"], name: "index_comments_on_commentable_and_created_at"
    t.index ["commentable_type", "commentable_id"], name: "index_comments_on_commentable"
    t.index ["deleted_at"], name: "index_comments_on_deleted_at"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "daily_rolls", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "reroll_value"
    t.date "rolled_on", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "value", null: false
    t.index ["rolled_on", "value"], name: "index_daily_rolls_on_rolled_on_and_value"
    t.index ["user_id", "rolled_on"], name: "index_daily_rolls_on_user_id_and_rolled_on", unique: true
    t.index ["user_id"], name: "index_daily_rolls_on_user_id"
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

  create_table "email_templates", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_email_templates_on_name", unique: true
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

  create_table "follows", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "followed_id", null: false
    t.bigint "follower_id", null: false
    t.datetime "updated_at", null: false
    t.index ["followed_id"], name: "index_follows_on_followed_id"
    t.index ["follower_id", "followed_id"], name: "index_follows_on_follower_id_and_followed_id", unique: true
    t.index ["follower_id"], name: "index_follows_on_follower_id"
    t.check_constraint "follower_id <> followed_id", name: "follows_no_self_follow"
  end

  create_table "fraud_payout_lines", force: :cascade do |t|
    t.integer "amount"
    t.datetime "created_at", null: false
    t.bigint "fraud_payout_run_id", null: false
    t.integer "order_count"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["fraud_payout_run_id"], name: "index_fraud_payout_lines_on_fraud_payout_run_id"
    t.index ["user_id"], name: "index_fraud_payout_lines_on_user_id"
  end

  create_table "fraud_payout_runs", force: :cascade do |t|
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
    t.index ["user_id", "reason"], name: "index_ledger_entries_unique_welcome_grant", unique: true, where: "((reason)::text = 'Free Stickers Welcome Grant'::text)"
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

  create_table "lookout_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "devlog_id"
    t.integer "duration_seconds", default: 0
    t.string "mode"
    t.bigint "project_id", null: false
    t.string "recording_url"
    t.datetime "started_at"
    t.string "status", default: "pending"
    t.datetime "stopped_at"
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["devlog_id"], name: "index_lookout_sessions_on_devlog_id"
    t.index ["project_id", "status"], name: "index_lookout_sessions_on_project_id_and_status"
    t.index ["project_id"], name: "index_lookout_sessions_on_project_id"
    t.index ["token"], name: "index_lookout_sessions_on_token", unique: true
    t.index ["user_id"], name: "index_lookout_sessions_on_user_id"
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

  create_table "mission_guide_variants", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "body_updated_at"
    t.datetime "created_at", null: false
    t.string "language", null: false
    t.bigint "mission_id", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index "mission_id, lower((language)::text)", name: "index_mission_guide_variants_unique_language", unique: true
    t.index ["mission_id"], name: "index_mission_guide_variants_on_mission_id"
  end

  create_table "mission_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "mission_id", null: false
    t.integer "role", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["mission_id", "user_id", "role"], name: "index_mission_memberships_unique", unique: true
    t.index ["mission_id"], name: "index_mission_memberships_on_mission_id"
    t.index ["user_id"], name: "index_mission_memberships_on_user_id"
  end

  create_table "mission_prerequisites", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "dependent_mission_id", null: false
    t.bigint "prerequisite_mission_id", null: false
    t.datetime "updated_at", null: false
    t.index ["dependent_mission_id"], name: "index_mission_prerequisites_on_dependent_mission_id"
    t.index ["prerequisite_mission_id", "dependent_mission_id"], name: "idx_mission_prereqs_unique", unique: true
    t.index ["prerequisite_mission_id"], name: "index_mission_prerequisites_on_prerequisite_mission_id"
  end

  create_table "mission_prizes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "mission_id", null: false
    t.integer "position", default: 0, null: false
    t.bigint "shop_item_id", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_mission_prizes_on_deleted_at"
    t.index ["mission_id", "shop_item_id"], name: "index_mission_prizes_active_unique", unique: true, where: "(deleted_at IS NULL)"
    t.index ["mission_id"], name: "index_mission_prizes_on_mission_id"
    t.index ["shop_item_id"], name: "index_mission_prizes_on_shop_item_id"
  end

  create_table "mission_section_completions", force: :cascade do |t|
    t.datetime "completed_at", null: false
    t.datetime "created_at", null: false
    t.bigint "mission_id", null: false
    t.bigint "mission_step_id", null: false
    t.bigint "project_id", null: false
    t.datetime "updated_at", null: false
    t.index ["mission_id"], name: "index_mission_section_completions_on_mission_id"
    t.index ["mission_step_id"], name: "index_mission_section_completions_on_mission_step_id"
    t.index ["project_id", "mission_step_id"], name: "index_mission_section_completions_unique", unique: true
    t.index ["project_id"], name: "index_mission_section_completions_on_project_id"
  end

  create_table "mission_shop_unlocks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "mission_id", null: false
    t.bigint "shop_item_id", null: false
    t.datetime "updated_at", null: false
    t.index ["mission_id", "shop_item_id"], name: "index_mission_shop_unlocks_unique", unique: true
    t.index ["mission_id"], name: "index_mission_shop_unlocks_on_mission_id"
    t.index ["shop_item_id"], name: "index_mission_shop_unlocks_on_shop_item_id"
  end

  create_table "mission_step_bodies", force: :cascade do |t|
    t.text "body", default: "", null: false
    t.datetime "body_updated_at"
    t.datetime "created_at", null: false
    t.string "language", null: false
    t.bigint "mission_step_id", null: false
    t.datetime "updated_at", null: false
    t.index "mission_step_id, lower((language)::text)", name: "index_mission_step_bodies_unique_language", unique: true
    t.index ["mission_step_id"], name: "index_mission_step_bodies_on_mission_step_id"
  end

  create_table "mission_steps", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "mission_id", null: false
    t.integer "position", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_mission_steps_on_deleted_at"
    t.index ["mission_id", "position"], name: "index_mission_steps_on_mission_id_and_position"
    t.index ["mission_id"], name: "index_mission_steps_on_mission_id"
  end

  create_table "mission_submissions", force: :cascade do |t|
    t.bigint "chosen_prize_id"
    t.datetime "claim_expires_at"
    t.datetime "claimed_at"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "mission_id", null: false
    t.string "payout_path", null: false
    t.datetime "pending_at"
    t.text "rejection_message"
    t.datetime "reviewed_at"
    t.bigint "reviewed_by_id"
    t.bigint "ship_event_id", null: false
    t.bigint "shop_order_id"
    t.string "status", null: false
    t.datetime "submission_guide_acknowledged_at"
    t.datetime "updated_at", null: false
    t.index ["chosen_prize_id"], name: "index_mission_submissions_on_chosen_prize_id"
    t.index ["deleted_at"], name: "index_mission_submissions_on_deleted_at"
    t.index ["mission_id", "status"], name: "index_mission_submissions_on_mission_id_and_status"
    t.index ["mission_id"], name: "index_mission_submissions_on_mission_id"
    t.index ["reviewed_by_id"], name: "index_mission_submissions_on_reviewed_by_id"
    t.index ["ship_event_id"], name: "index_mission_submissions_active_per_ship_event", unique: true, where: "(deleted_at IS NULL)"
    t.index ["ship_event_id"], name: "index_mission_submissions_on_ship_event_id"
    t.index ["shop_order_id"], name: "index_mission_submissions_on_shop_order_id"
    t.index ["shop_order_id"], name: "index_mission_submissions_with_shop_order", where: "(shop_order_id IS NOT NULL)"
    t.index ["status", "claim_expires_at"], name: "idx_mission_submissions_on_status_claim_expires"
    t.index ["status", "created_at"], name: "index_mission_submissions_on_status_and_created_at"
    t.index ["status", "pending_at"], name: "index_mission_submissions_on_status_and_pending_at"
  end

  create_table "missions", force: :cascade do |t|
    t.text "achievement_description"
    t.string "achievement_name"
    t.datetime "created_at", null: false
    t.text "default_project_description"
    t.string "default_project_title"
    t.datetime "deleted_at"
    t.text "description", null: false
    t.string "difficulty"
    t.boolean "enabled", default: true, null: false
    t.datetime "end_at"
    t.integer "estimated_completion_minutes"
    t.datetime "featured_at"
    t.integer "fixed_stardust_payout"
    t.integer "guide_sections_count"
    t.string "guide_url"
    t.boolean "hardware", default: false, null: false
    t.string "name", null: false
    t.integer "prizes_count", default: 0, null: false
    t.string "slug", null: false
    t.datetime "start_at"
    t.integer "steps_count", default: 0, null: false
    t.text "submission_guide"
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_missions_on_deleted_at"
    t.index ["enabled"], name: "index_missions_on_enabled"
    t.index ["featured_at"], name: "index_missions_on_featured_at"
    t.index ["slug"], name: "index_missions_on_slug", unique: true
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "actor_id"
    t.datetime "created_at", null: false
    t.datetime "email_delivered_at"
    t.integer "group_count", default: 1, null: false
    t.string "group_key"
    t.jsonb "params", default: {}, null: false
    t.integer "priority", default: 0, null: false
    t.datetime "read_at"
    t.bigint "recipient_id", null: false
    t.bigint "record_id"
    t.string "record_type"
    t.datetime "seen_at"
    t.datetime "slack_enqueued_at"
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_notifications_on_actor_id"
    t.index ["recipient_id", "created_at"], name: "index_notifications_on_recipient_id_and_created_at"
    t.index ["recipient_id", "group_key", "read_at"], name: "index_notifications_on_recipient_id_and_group_key_and_read_at", where: "(group_key IS NOT NULL)"
    t.index ["recipient_id", "seen_at"], name: "index_notifications_on_recipient_id_and_seen_at"
    t.index ["recipient_id", "type", "group_key"], name: "index_notifications_unique_unread_aggregate", unique: true, where: "((read_at IS NULL) AND (group_key IS NOT NULL))"
    t.index ["recipient_id"], name: "index_notifications_on_recipient_id"
    t.index ["record_type", "record_id"], name: "index_notifications_on_record_type_and_record_id"
    t.index ["type", "created_at"], name: "index_notifications_on_type_and_created_at"
  end

  create_table "post_devlogs", force: :cascade do |t|
    t.string "body"
    t.integer "comments_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.integer "duration_seconds"
    t.text "hackatime_projects_key_snapshot"
    t.datetime "hackatime_pulled_at"
    t.integer "likes_count", default: 0, null: false
    t.string "phase"
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

  create_table "post_reposts", force: :cascade do |t|
    t.string "body"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "original_post_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["deleted_at"], name: "index_post_reposts_on_deleted_at"
    t.index ["original_post_id", "user_id"], name: "index_post_reposts_active_unique", unique: true, where: "(deleted_at IS NULL)"
    t.index ["original_post_id"], name: "index_post_reposts_on_original_post_id"
    t.index ["user_id"], name: "index_post_reposts_on_user_id"
  end

  create_table "post_ship_events", force: :cascade do |t|
    t.string "body"
    t.string "certification_status", default: "pending"
    t.datetime "created_at", null: false
    t.text "feedback_reason"
    t.string "feedback_video_url"
    t.float "hours_at_payout"
    t.float "hours_at_ship"
    t.float "multiplier"
    t.decimal "originality_median", precision: 5, scale: 2
    t.decimal "originality_percentile", precision: 5, scale: 2
    t.decimal "overall_percentile", precision: 5, scale: 2
    t.decimal "overall_score", precision: 5, scale: 2
    t.float "payout"
    t.datetime "payout_basis_locked_at"
    t.decimal "payout_basis_overall_score", precision: 5, scale: 2
    t.decimal "payout_basis_percentile", precision: 5, scale: 2
    t.bigint "payout_basis_vote_ids", default: [], null: false, array: true
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
  end

  create_table "post_views", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "post_id", null: false
    t.datetime "read_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["post_id", "user_id"], name: "index_post_views_on_post_id_and_user_id", unique: true
    t.index ["user_id"], name: "index_post_views_on_user_id"
  end

  create_table "posts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "postable_id"
    t.string "postable_type"
    t.bigint "project_id"
    t.integer "reposts_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.integer "views_count", default: 0, null: false
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

  create_table "project_mission_attachments", force: :cascade do |t|
    t.datetime "attached_at", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.datetime "detached_at"
    t.bigint "mission_id", null: false
    t.bigint "project_id", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_project_mission_attachments_on_deleted_at"
    t.index ["mission_id"], name: "index_project_mission_attachments_on_mission_id"
    t.index ["project_id", "mission_id"], name: "index_project_mission_attachments_active", unique: true, where: "((detached_at IS NULL) AND (deleted_at IS NULL))"
    t.index ["project_id"], name: "index_project_mission_attachments_on_project_id"
    t.index ["project_id"], name: "index_project_mission_attachments_one_active", unique: true, where: "((detached_at IS NULL) AND (deleted_at IS NULL))"
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
    t.string "hardware_stage"
    t.datetime "marked_fire_at"
    t.bigint "marked_fire_by_id"
    t.integer "memberships_count", default: 0, null: false
    t.datetime "nominated_fire_at"
    t.bigint "nominated_fire_by_id"
    t.string "project_categories", default: [], array: true
    t.string "project_type"
    t.text "readme_url"
    t.text "repo_url"
    t.string "ship_status", default: "draft"
    t.datetime "shipped_at"
    t.datetime "synced_at"
    t.string "title", null: false
    t.boolean "tutorial", default: false, null: false
    t.text "update_description"
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_projects_on_deleted_at"
    t.index ["marked_fire_by_id"], name: "index_projects_on_marked_fire_by_id"
    t.index ["nominated_fire_by_id"], name: "index_projects_on_nominated_fire_by_id"
  end

  create_table "raffle_draws", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "drawn_at", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.text "void_reason"
    t.datetime "voided_at"
    t.bigint "week_id", null: false
    t.bigint "winner_participant_id", null: false
    t.index ["week_id", "status"], name: "index_raffle_draws_on_week_id_and_status"
    t.index ["week_id"], name: "index_raffle_draws_on_week_id"
    t.index ["winner_participant_id"], name: "index_raffle_draws_on_winner_participant_id"
  end

  create_table "raffle_participants", force: :cascade do |t|
    t.string "age_group", default: "teen", null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.boolean "eligible", default: true, null: false
    t.boolean "fraud_cleared", default: false, null: false
    t.string "github_avatar_url"
    t.string "github_login"
    t.string "github_uid"
    t.bigint "signup_week_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["code"], name: "index_raffle_participants_on_code", unique: true
    t.index ["github_uid"], name: "index_raffle_participants_on_github_uid_unique", unique: true, where: "(github_uid IS NOT NULL)"
    t.index ["user_id"], name: "index_raffle_participants_on_user_id_unique", unique: true, where: "(user_id IS NOT NULL)"
  end

  create_table "raffle_referrals", force: :cascade do |t|
    t.string "channel", default: "web", null: false
    t.datetime "created_at", null: false
    t.bigint "credited_week_id"
    t.bigint "participant_id", null: false
    t.string "raw_ref"
    t.bigint "referred_user_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.datetime "verified_at"
    t.index ["credited_week_id", "status", "participant_id"], name: "index_raffle_referrals_on_week_status_participant"
    t.index ["participant_id", "status", "credited_week_id"], name: "index_raffle_referrals_on_participant_status_week"
    t.index ["referred_user_id"], name: "index_raffle_referrals_on_referred_user_id", unique: true
    t.index ["status", "created_at"], name: "index_raffle_referrals_on_status_created_at"
  end

  create_table "raffle_weekly_claims", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "participant_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "week_id", null: false
    t.index ["participant_id", "week_id"], name: "index_raffle_weekly_claims_on_participant_id_and_week_id", unique: true
    t.index ["participant_id"], name: "index_raffle_weekly_claims_on_participant_id"
    t.index ["week_id"], name: "index_raffle_weekly_claims_on_week_id"
  end

  create_table "raffle_weeks", force: :cascade do |t|
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.datetime "drawn_at"
    t.integer "number", null: false
    t.datetime "opened_at"
    t.string "prize", default: "AMD RX 9060 XT", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.bigint "winner_participant_id"
    t.index ["number"], name: "index_raffle_weeks_on_number", unique: true
    t.index ["status"], name: "index_raffle_weeks_one_active", unique: true, where: "((status)::text = 'active'::text)"
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

  create_table "reviewer_payout_requests", force: :cascade do |t|
    t.string "aasm_state", default: "pending", null: false
    t.text "adjust_reason"
    t.integer "adjusted_amount"
    t.bigint "admin_id"
    t.integer "amount", null: false
    t.datetime "created_at", null: false
    t.integer "paid_amount"
    t.datetime "paid_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["admin_id"], name: "index_reviewer_payout_requests_on_admin_id"
    t.index ["user_id"], name: "index_reviewer_payout_requests_on_user_id"
    t.index ["user_id"], name: "index_reviewer_payout_requests_on_user_id_pending", unique: true, where: "((aasm_state)::text = 'pending'::text)"
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
    t.string "geocoded_country"
    t.float "geocoded_lat"
    t.float "geocoded_lon"
    t.string "geocoded_subdivision"
    t.string "ip_address"
    t.string "ref"
    t.datetime "reply_confirmed_at"
    t.datetime "signup_confirmation_sent_at"
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.string "user_ref"
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

  create_table "shop_categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hub_title", null: false
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["position"], name: "index_shop_categories_on_position"
    t.index ["slug"], name: "index_shop_categories_on_slug", unique: true
  end

  create_table "shop_item_attachments", force: :cascade do |t|
    t.bigint "accessory_item_id", null: false
    t.datetime "created_at", null: false
    t.bigint "parent_item_id", null: false
    t.datetime "updated_at", null: false
    t.index ["accessory_item_id"], name: "index_shop_item_attachments_on_accessory_item_id"
    t.index ["parent_item_id", "accessory_item_id"], name: "idx_on_parent_item_id_accessory_item_id_9641b2d0dd", unique: true
    t.index ["parent_item_id"], name: "index_shop_item_attachments_on_parent_item_id"
  end

  create_table "shop_item_categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "shop_category_id", null: false
    t.bigint "shop_item_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_category_id"], name: "index_shop_item_categories_on_shop_category_id"
    t.index ["shop_item_id", "shop_category_id"], name: "index_shop_item_categories_unique", unique: true
    t.index ["shop_item_id"], name: "index_shop_item_categories_on_shop_item_id"
  end

  create_table "shop_item_modifiers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.boolean "enabled_au"
    t.boolean "enabled_ca"
    t.boolean "enabled_eu"
    t.boolean "enabled_in"
    t.boolean "enabled_uk"
    t.boolean "enabled_us"
    t.boolean "enabled_xx"
    t.string "group_name"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.bigint "shop_item_id", null: false
    t.integer "ticket_cost", default: 0, null: false
    t.datetime "updated_at", null: false
    t.decimal "usd_cost", precision: 10, scale: 2
    t.decimal "usd_offset_au", precision: 10, scale: 2
    t.decimal "usd_offset_ca", precision: 10, scale: 2
    t.decimal "usd_offset_eu", precision: 10, scale: 2
    t.decimal "usd_offset_in", precision: 10, scale: 2
    t.decimal "usd_offset_uk", precision: 10, scale: 2
    t.decimal "usd_offset_us", precision: 10, scale: 2
    t.decimal "usd_offset_xx", precision: 10, scale: 2
    t.index ["shop_item_id"], name: "index_shop_item_modifiers_on_shop_item_id"
  end

  create_table "shop_item_sources", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "shop_item_id", null: false
    t.bigint "shop_source_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_item_id", "shop_source_id"], name: "index_shop_item_sources_unique", unique: true
    t.index ["shop_item_id"], name: "index_shop_item_sources_on_shop_item_id"
    t.index ["shop_source_id"], name: "index_shop_item_sources_on_shop_source_id"
  end

  create_table "shop_items", force: :cascade do |t|
    t.string "accessory_tag"
    t.jsonb "agh_contents"
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
    t.boolean "mission_prize_only", default: false, null: false
    t.string "name"
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
    t.index ["mission_prize_only"], name: "index_shop_items_on_mission_prize_only"
    t.index ["user_id"], name: "index_shop_items_on_user_id"
  end

  create_table "shop_order_modifier_selections", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "frozen_modifier_price", default: 0, null: false
    t.bigint "shop_item_modifier_id", null: false
    t.bigint "shop_order_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_item_modifier_id"], name: "index_shop_order_modifier_selections_on_shop_item_modifier_id"
    t.index ["shop_order_id", "shop_item_modifier_id"], name: "idx_modifier_selections_unique", unique: true
    t.index ["shop_order_id"], name: "index_shop_order_modifier_selections_on_shop_order_id"
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
    t.bigint "assigned_to_user_id"
    t.datetime "awaiting_periodical_fulfillment_at"
    t.datetime "created_at", null: false
    t.string "external_ref"
    t.bigint "fraud_payout_line_id"
    t.bigint "fraud_related_project_id"
    t.text "frozen_address_ciphertext"
    t.decimal "frozen_item_price", precision: 6, scale: 2
    t.integer "frozen_modifiers_price", default: 0, null: false
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

  create_table "shop_sources", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["position"], name: "index_shop_sources_on_position"
    t.index ["slug"], name: "index_shop_sources_on_slug", unique: true
  end

  create_table "shop_suggestion_votes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "shop_suggestion_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["shop_suggestion_id"], name: "index_shop_suggestion_votes_on_shop_suggestion_id"
    t.index ["user_id"], name: "index_shop_suggestion_votes_on_user_id"
  end

  create_table "shop_suggestions", force: :cascade do |t|
    t.string "aasm_state", default: "pending", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "discarded_at"
    t.text "name"
    t.string "rejection_reason"
    t.bigint "shop_item_id"
    t.datetime "updated_at", null: false
    t.string "url"
    t.decimal "usd_cost", precision: 8, scale: 2
    t.bigint "user_id", null: false
    t.index ["aasm_state"], name: "index_shop_suggestions_on_aasm_state"
    t.index ["shop_item_id"], name: "index_shop_suggestions_on_shop_item_id"
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

  create_table "shop_wishlists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "shop_item_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["shop_item_id"], name: "index_shop_wishlists_on_shop_item_id"
    t.index ["user_id", "shop_item_id"], name: "index_shop_wishlists_on_user_id_and_shop_item_id", unique: true
    t.index ["user_id"], name: "index_shop_wishlists_on_user_id"
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

  create_table "streak_activities", force: :cascade do |t|
    t.date "activity_date", null: false
    t.integer "coded_seconds", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "activity_date"], name: "index_streak_activities_on_user_id_and_activity_date", unique: true
    t.index ["user_id"], name: "index_streak_activities_on_user_id"
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

  create_table "user_notification_preferences", force: :cascade do |t|
    t.string "category", null: false
    t.datetime "created_at", null: false
    t.boolean "email_enabled"
    t.boolean "in_app_enabled"
    t.boolean "slack_enabled"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "category"], name: "index_user_notification_preferences_on_user_id_and_category", unique: true
    t.index ["user_id"], name: "index_user_notification_preferences_on_user_id"
  end

  create_table "user_preferences", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "leaderboard_optin", default: false, null: false
    t.boolean "search_engine_indexing_off", default: false, null: false
    t.boolean "send_notifications_for_followed_projects", default: true, null: false
    t.boolean "send_notifications_for_followed_users", default: true, null: false
    t.boolean "send_notifications_for_new_comments", default: true, null: false
    t.boolean "send_notifications_for_new_followers", default: true, null: false
    t.boolean "send_votes_to_slack", default: false, null: false
    t.boolean "stardust_balance_notifications", default: false, null: false
    t.boolean "streak_slack_status_enabled", default: true, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["leaderboard_optin"], name: "index_user_preferences_on_leaderboard_optin"
    t.index ["user_id"], name: "index_user_preferences_on_user_id", unique: true
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
    t.string "age_attestation"
    t.integer "approx_balance", default: 0, null: false
    t.integer "approx_total_earned", default: 0, null: false
    t.boolean "banned", default: false, null: false
    t.datetime "banned_at"
    t.text "banned_reason"
    t.text "bio"
    t.datetime "created_at", null: false
    t.integer "current_streak", default: 0, null: false
    t.string "display_name"
    t.string "email"
    t.string "enriched_ref"
    t.string "experience_level"
    t.string "first_name"
    t.string "geocoded_country"
    t.float "geocoded_lat"
    t.float "geocoded_lon"
    t.string "geocoded_subdivision"
    t.string "granted_roles", default: [], null: false, array: true
    t.string "guest_email"
    t.boolean "has_gotten_free_stickers", default: false
    t.boolean "has_pending_achievements", default: false, null: false
    t.string "hcb_email"
    t.string "interests", default: [], array: true
    t.text "internal_notes"
    t.string "ip_address"
    t.string "last_name"
    t.string "manual_outpost_ticket_approval"
    t.boolean "manual_ysws_override"
    t.boolean "mission_review_notifications", default: true, null: false
    t.datetime "onboarded_at"
    t.integer "outpost_discount_stardust", default: 0, null: false
    t.datetime "outpost_email_sent_at"
    t.string "ref"
    t.string "regions", default: [], array: true
    t.string "session_token"
    t.enum "shop_region", enum_type: "shop_region_type"
    t.datetime "shop_tutorial_completed_at"
    t.datetime "shop_tutorial_started_at"
    t.string "slack_id"
    t.datetime "streak_synced_at"
    t.datetime "synced_at"
    t.string "things_dismissed", default: [], null: false, array: true
    t.string "timezone"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.string "user_ref"
    t.datetime "verification_checked_at"
    t.string "verification_status", default: "needs_submission", null: false
    t.integer "vote_balance", default: 0, null: false
    t.integer "votes_count"
    t.boolean "ysws_eligible", default: false, null: false
    t.index "lower((display_name)::text)", name: "index_users_on_lower_display_name_unique", unique: true, where: "((display_name IS NOT NULL) AND ((display_name)::text <> ''::text))"
    t.index "lower((email)::text)", name: "index_users_on_lower_email_unique", unique: true, where: "((email IS NOT NULL) AND ((email)::text <> ''::text))"
    t.index ["approx_balance"], name: "index_users_on_approx_balance", order: :desc
    t.index ["approx_total_earned"], name: "index_users_on_approx_total_earned", order: :desc
    t.index ["email"], name: "index_users_on_email"
    t.index ["guest_email"], name: "index_users_on_guest_email"
    t.index ["onboarded_at"], name: "index_users_on_onboarded_at"
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

  create_table "vote_assignments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "first_viewed_at"
    t.datetime "last_viewed_at"
    t.bigint "ship_event_id", null: false
    t.datetime "skipped_at"
    t.string "status", default: "assigned", null: false
    t.datetime "submitted_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "view_count", default: 0, null: false
    t.bigint "vote_id"
    t.index ["ship_event_id"], name: "index_vote_assignments_on_ship_event_id"
    t.index ["user_id", "ship_event_id"], name: "index_vote_assignments_on_user_id_and_ship_event_id", unique: true
    t.index ["user_id", "status"], name: "index_vote_assignments_on_user_id_and_status"
    t.index ["user_id"], name: "index_vote_assignments_on_user_id"
    t.index ["vote_id"], name: "index_vote_assignments_on_vote_id"
  end

  create_table "vote_events", force: :cascade do |t|
    t.bigint "ahoy_visit_id"
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.string "ip"
    t.datetime "occurred_at", null: false
    t.bigint "project_id"
    t.jsonb "properties", default: {}, null: false
    t.bigint "ship_event_id"
    t.string "source", default: "server", null: false
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.bigint "user_id", null: false
    t.bigint "vote_assignment_id"
    t.bigint "vote_id"
    t.index ["ahoy_visit_id"], name: "index_vote_events_on_ahoy_visit_id"
    t.index ["event_type", "occurred_at"], name: "index_vote_events_on_event_type_and_occurred_at"
    t.index ["project_id"], name: "index_vote_events_on_project_id"
    t.index ["properties"], name: "index_vote_events_on_properties", opclass: :jsonb_path_ops, using: :gin
    t.index ["ship_event_id"], name: "index_vote_events_on_ship_event_id"
    t.index ["user_id"], name: "index_vote_events_on_user_id"
    t.index ["vote_assignment_id"], name: "index_vote_events_on_vote_assignment_id"
    t.index ["vote_id"], name: "index_vote_events_on_vote_id"
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
    t.boolean "demo_opened", default: false, null: false
    t.boolean "discarded", default: false, null: false
    t.integer "originality_score"
    t.bigint "project_id", null: false
    t.text "reason"
    t.boolean "repo_opened", default: false, null: false
    t.bigint "ship_event_id", null: false
    t.integer "storytelling_score"
    t.integer "technical_score"
    t.integer "time_taken_to_vote_in_seconds"
    t.datetime "updated_at", null: false
    t.integer "usability_score"
    t.bigint "user_id", null: false
    t.index ["discarded", "ship_event_id"], name: "index_votes_on_discarded_and_ship_event_id"
    t.index ["project_id"], name: "index_votes_on_project_id"
    t.index ["ship_event_id"], name: "index_votes_on_ship_event_id"
    t.index ["user_id", "ship_event_id"], name: "index_votes_on_user_id_and_ship_event_id", unique: true
    t.index ["user_id"], name: "index_votes_on_user_id"
  end

  create_table "workshop_attendances", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "workshop_id", null: false
    t.index ["user_id"], name: "index_workshop_attendances_on_user_id"
    t.index ["workshop_id", "user_id"], name: "index_workshop_attendances_on_workshop_id_and_user_id", unique: true
  end

  create_table "workshop_rsvps", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "workshop_id", null: false
    t.index ["user_id"], name: "index_workshop_rsvps_on_user_id"
    t.index ["workshop_id", "user_id"], name: "index_workshop_rsvps_on_workshop_id_and_user_id", unique: true
  end

  create_table "workshops", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "ends_at", null: false
    t.datetime "rsvps_notified_at"
    t.datetime "starts_at", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "zoom_link"
    t.index ["starts_at"], name: "index_workshops_on_starts_at"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "certificates", "users"
  add_foreign_key "certification_devlog_reviews", "certification_ysws_reviews", column: "ysws_review_id"
  add_foreign_key "certification_devlog_reviews", "post_devlogs"
  add_foreign_key "certification_funding_requests", "projects"
  add_foreign_key "certification_funding_requests", "users"
  add_foreign_key "certification_funding_requests", "users", column: "reviewer_id"
  add_foreign_key "certification_integrities", "post_ship_events", column: "ship_event_id"
  add_foreign_key "certification_integrities", "users", column: "claimed_by_id"
  add_foreign_key "certification_integrities", "users", column: "reviewer_id"
  add_foreign_key "certification_ship_reviews", "post_ship_events", on_delete: :nullify
  add_foreign_key "certification_ship_reviews", "projects"
  add_foreign_key "certification_ship_reviews", "users", column: "reviewer_id"
  add_foreign_key "certification_ysws_reviews", "certification_ship_reviews", column: "ship_cert_id"
  add_foreign_key "certification_ysws_reviews", "post_ship_events"
  add_foreign_key "certification_ysws_reviews", "projects"
  add_foreign_key "certification_ysws_reviews", "users"
  add_foreign_key "certification_ysws_reviews", "users", column: "claimed_by_id"
  add_foreign_key "certification_ysws_reviews", "users", column: "reviewer_id"
  add_foreign_key "certification_ysws_reviews", "users", column: "spotchecked_by_id"
  add_foreign_key "comments", "users"
  add_foreign_key "daily_rolls", "users"
  add_foreign_key "devlog_versions", "post_devlogs", column: "devlog_id"
  add_foreign_key "devlog_versions", "users"
  add_foreign_key "follows", "users", column: "followed_id"
  add_foreign_key "follows", "users", column: "follower_id"
  add_foreign_key "fraud_payout_lines", "fraud_payout_runs"
  add_foreign_key "fraud_payout_lines", "users"
  add_foreign_key "fulfillment_payout_lines", "fulfillment_payout_runs"
  add_foreign_key "fulfillment_payout_lines", "users"
  add_foreign_key "fulfillment_payout_runs", "users", column: "approved_by_user_id"
  add_foreign_key "ledger_entries", "users"
  add_foreign_key "likes", "users"
  add_foreign_key "lookout_sessions", "post_devlogs", column: "devlog_id"
  add_foreign_key "lookout_sessions", "projects"
  add_foreign_key "lookout_sessions", "users"
  add_foreign_key "messages", "users"
  add_foreign_key "messages", "users", column: "sent_by_id"
  add_foreign_key "mission_guide_variants", "missions"
  add_foreign_key "mission_memberships", "missions"
  add_foreign_key "mission_memberships", "users"
  add_foreign_key "mission_prerequisites", "missions", column: "dependent_mission_id"
  add_foreign_key "mission_prerequisites", "missions", column: "prerequisite_mission_id"
  add_foreign_key "mission_prizes", "missions"
  add_foreign_key "mission_prizes", "shop_items"
  add_foreign_key "mission_section_completions", "mission_steps", on_delete: :cascade
  add_foreign_key "mission_section_completions", "missions"
  add_foreign_key "mission_section_completions", "projects"
  add_foreign_key "mission_shop_unlocks", "missions"
  add_foreign_key "mission_shop_unlocks", "shop_items"
  add_foreign_key "mission_step_bodies", "mission_steps"
  add_foreign_key "mission_steps", "missions"
  add_foreign_key "mission_submissions", "mission_prizes", column: "chosen_prize_id"
  add_foreign_key "mission_submissions", "missions"
  add_foreign_key "mission_submissions", "post_ship_events", column: "ship_event_id"
  add_foreign_key "mission_submissions", "shop_orders"
  add_foreign_key "mission_submissions", "users", column: "reviewed_by_id"
  add_foreign_key "notifications", "users", column: "actor_id", on_delete: :nullify
  add_foreign_key "notifications", "users", column: "recipient_id", on_delete: :cascade
  add_foreign_key "post_reposts", "posts", column: "original_post_id"
  add_foreign_key "post_reposts", "users"
  add_foreign_key "post_views", "posts"
  add_foreign_key "post_views", "users"
  add_foreign_key "posts", "projects"
  add_foreign_key "posts", "users"
  add_foreign_key "project_follows", "projects"
  add_foreign_key "project_follows", "users"
  add_foreign_key "project_memberships", "projects"
  add_foreign_key "project_memberships", "users"
  add_foreign_key "project_mission_attachments", "missions"
  add_foreign_key "project_mission_attachments", "projects"
  add_foreign_key "project_reports", "projects"
  add_foreign_key "project_reports", "users", column: "reporter_id"
  add_foreign_key "project_skips", "projects"
  add_foreign_key "project_skips", "users"
  add_foreign_key "projects", "users", column: "marked_fire_by_id"
  add_foreign_key "projects", "users", column: "nominated_fire_by_id"
  add_foreign_key "raffle_draws", "raffle_participants", column: "winner_participant_id"
  add_foreign_key "raffle_draws", "raffle_weeks", column: "week_id"
  add_foreign_key "raffle_participants", "raffle_weeks", column: "signup_week_id"
  add_foreign_key "raffle_participants", "users"
  add_foreign_key "raffle_referrals", "raffle_participants", column: "participant_id"
  add_foreign_key "raffle_referrals", "raffle_weeks", column: "credited_week_id"
  add_foreign_key "raffle_referrals", "users", column: "referred_user_id"
  add_foreign_key "raffle_weekly_claims", "raffle_participants", column: "participant_id"
  add_foreign_key "raffle_weekly_claims", "raffle_weeks", column: "week_id"
  add_foreign_key "raffle_weeks", "raffle_participants", column: "winner_participant_id"
  add_foreign_key "report_review_tokens", "project_reports", column: "report_id"
  add_foreign_key "reviewer_payout_requests", "users"
  add_foreign_key "reviewer_payout_requests", "users", column: "admin_id"
  add_foreign_key "rsvp_games", "rsvps"
  add_foreign_key "rsvp_replies", "rsvps"
  add_foreign_key "shop_card_grants", "shop_items"
  add_foreign_key "shop_card_grants", "users"
  add_foreign_key "shop_item_attachments", "shop_items", column: "accessory_item_id", on_delete: :cascade
  add_foreign_key "shop_item_attachments", "shop_items", column: "parent_item_id", on_delete: :cascade
  add_foreign_key "shop_item_categories", "shop_categories"
  add_foreign_key "shop_item_categories", "shop_items"
  add_foreign_key "shop_item_modifiers", "shop_items"
  add_foreign_key "shop_item_sources", "shop_items"
  add_foreign_key "shop_item_sources", "shop_sources"
  add_foreign_key "shop_items", "users"
  add_foreign_key "shop_items", "users", column: "created_by_user_id", on_delete: :nullify, validate: false
  add_foreign_key "shop_items", "users", column: "default_assigned_user_id", on_delete: :nullify
  add_foreign_key "shop_order_modifier_selections", "shop_item_modifiers"
  add_foreign_key "shop_order_modifier_selections", "shop_orders"
  add_foreign_key "shop_order_reviews", "shop_orders"
  add_foreign_key "shop_order_reviews", "users"
  add_foreign_key "shop_orders", "fulfillment_payout_lines"
  add_foreign_key "shop_orders", "shop_items"
  add_foreign_key "shop_orders", "shop_orders", column: "parent_order_id"
  add_foreign_key "shop_orders", "shop_warehouse_packages", column: "warehouse_package_id"
  add_foreign_key "shop_orders", "users"
  add_foreign_key "shop_orders", "users", column: "assigned_to_user_id", on_delete: :nullify
  add_foreign_key "shop_suggestion_votes", "shop_suggestions"
  add_foreign_key "shop_suggestion_votes", "users"
  add_foreign_key "shop_suggestions", "users"
  add_foreign_key "shop_warehouse_packages", "users"
  add_foreign_key "shop_wishlists", "shop_items"
  add_foreign_key "shop_wishlists", "users"
  add_foreign_key "show_and_tell_attendances", "projects"
  add_foreign_key "show_and_tell_attendances", "users"
  add_foreign_key "show_and_tell_attendances", "users", column: "payout_given_by_id"
  add_foreign_key "show_and_tell_payout_records", "users", column: "payout_given_by_id"
  add_foreign_key "streak_activities", "users"
  add_foreign_key "user_achievements", "users"
  add_foreign_key "user_hackatime_projects", "projects"
  add_foreign_key "user_hackatime_projects", "users"
  add_foreign_key "user_identities", "users"
  add_foreign_key "user_notification_preferences", "users", on_delete: :cascade
  add_foreign_key "user_preferences", "users"
  add_foreign_key "user_vote_verdicts", "users"
  add_foreign_key "vote_assignments", "post_ship_events", column: "ship_event_id"
  add_foreign_key "vote_assignments", "users"
  add_foreign_key "vote_assignments", "votes"
  add_foreign_key "vote_events", "post_ship_events", column: "ship_event_id"
  add_foreign_key "vote_events", "projects"
  add_foreign_key "vote_events", "users"
  add_foreign_key "vote_events", "vote_assignments"
  add_foreign_key "vote_events", "votes"
  add_foreign_key "votes", "post_ship_events", column: "ship_event_id"
  add_foreign_key "votes", "projects"
  add_foreign_key "votes", "users"
  add_foreign_key "workshop_attendances", "users"
  add_foreign_key "workshop_attendances", "workshops"
  add_foreign_key "workshop_rsvps", "users"
  add_foreign_key "workshop_rsvps", "workshops"
end
