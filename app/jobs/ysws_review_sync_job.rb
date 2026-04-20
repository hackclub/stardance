=begin
Put this into https://mermaid.live/ for a visualisation of the pipeline.

flowchart TD
    Start(["`**process_review(review_id)**`"]) --> Init["adjusted_hours = nil"]
    Init --> FetchReview["Fetch review from YSWS API"]
    FetchReview --> GetDevlogs["Extract devlogs from review"]
    GetDevlogs --> CalcMinutes["total_approved_minutes = sum of approvedMins"]

    CalcMinutes --> CheckMinutes{"`total_approved_minutes < 5?`"}
    CheckMinutes -->|Yes| SkipLowMinutes(["`⛔ SKIP
    Less than 5 approved minutes`"])

    CheckMinutes -->|No| ExtractShipCert["Extract from shipCert:
    • code_url = repoUrl
    • ft_project_id = ftProjectId"]

    ExtractShipCert --> CheckReports{"`Project has pending
    or reviewed reports?`"}
    CheckReports -->|Yes| SkipReports(["`⛔ SKIP
    Active reports exist`"])

    CheckReports -->|No| CheckCodeUrl{"`code_url.present?`"}

    CheckCodeUrl -->|No| GoToSlackCheck
    CheckCodeUrl -->|Yes| CheckFlavortown{"`Project in unified DB
    with YSWS = 'Flavortown'?`"}

    subgraph UnifiedDB["Unified Database Checks"]
        CheckFlavortown -->|Yes, found record| GetExistingHours["existing_hours = record hours
        new_hours = approved_mins / 60"]
        GetExistingHours --> CompareHoursFT{"`new_hours >
        existing_hours + 0.5?`"}
        CompareHoursFT -->|Yes| UpdateRecord["Update existing record:
        • Set new hours
        • Append justification"]
        UpdateRecord --> ReturnAfterUpdate(["`✅ RETURN
        Record updated`"])
        CompareHoursFT -->|No| SkipExistsFT(["`⛔ SKIP
        Hours not greater`"])

        CheckFlavortown -->|No| CheckUnifiedOther{"`Project in unified DB
        (non-Flavortown)?`"}
        CheckUnifiedOther -->|Yes| GetUnifiedHours["unified_db_hours = existing hours
        new_hours = approved_mins / 60"]
        GetUnifiedHours --> CompareHoursUnified{"`new_hours >
        unified_hours + 0.5?`"}
        CompareHoursUnified -->|Yes| SetAdjusted["adjusted_hours =
        new_hours - unified_hours"]
        SetAdjusted --> GoToSlackCheck
        CompareHoursUnified -->|No| SkipExistsUnified(["`⛔ SKIP
        Hours not greater`"])
        CheckUnifiedOther -->|No| GoToSlackCheck
    end

    GoToSlackCheck["slack_id = shipCert.ftSlackId"]
    GoToSlackCheck --> CheckSlackId{"`slack_id.blank?`"}
    CheckSlackId -->|Yes| SkipNoSlack(["`⛔ RETURN
    No slack_id`"])

    CheckSlackId -->|No| FindUser["user = User.find_by(slack_id)"]
    FindUser --> CheckUser{"`user.nil?`"}
    CheckUser -->|Yes| SkipNoUser(["`⛔ RETURN
    User not found`"])

    CheckUser -->|No| QueryOrders["Query user.shop_orders:
    • state = 'fulfilled'
    • NOT fulfilled_by LIKE 'System%'"]

    QueryOrders --> CheckOrders{"`approved_orders.none?`"}
    CheckOrders -->|Yes| SkipNoOrders(["`⛔ SKIP
    No manual orders`"])

    CheckOrders -->|No| ExtractPII["extract_user_pii(user)
    • slack_id, email, names
    • addresses, birthday"]

    ExtractPII --> CreateRecord["create_airtable_record
    • Build record fields
    • Upsert by ship_cert_id"]
    CreateRecord --> End(["`✅ SUCCESS
    Record synced to Airtable`"])

    class SkipLowMinutes,SkipReports,SkipExistsFT,SkipExistsUnified,SkipNoSlack,SkipNoUser,SkipNoOrders skip
    class End,ReturnAfterUpdate success
    class CheckMinutes,CheckReports,CheckCodeUrl,CheckFlavortown,CompareHoursFT,CheckUnifiedOther,CompareHoursUnified,CheckSlackId,CheckUser,CheckOrders decision
    class Start,Init,FetchReview,GetDevlogs,CalcMinutes,ExtractShipCert,GetExistingHours,UpdateRecord,GetUnifiedHours,SetAdjusted,GoToSlackCheck,FindUser,QueryOrders,ExtractPII,CreateRecord process
=end

class YswsReviewSyncJob < ApplicationJob
  include Rails.application.routes.url_helpers

  queue_as :default

  def self.perform_later(*args)
    return if SolidQueue::Job.where(class_name: name, finished_at: nil).exists?

    super
  end

  def perform
    hours = 24000 # YswsReviewService.hours_since_last_sync
    Rails.logger.info "[YswsReviewSyncJob] Fetching reviews from last #{hours} hours"

    reviews_response = YswsReviewService.fetch_reviews(hours: hours, status: "done")
    reviews = reviews_response["reviews"] || []

    Rails.logger.info "[YswsReviewSyncJob] Found #{reviews.count} reviews to sync"

    reviews.each do |review_summary|
      process_review(review_summary["id"])
    rescue StandardError => e
      Rails.logger.error "[YswsReviewSyncJob] Error processing review #{review_summary['id']}: #{e.message}"
      Sentry.capture_exception(e, extra: { review_id: review_summary["id"] })
    end

    YswsReviewService.update_last_synced_at!
  end

  private

  def process_review(review_id)
    adjusted_hours = nil
    @rejected_project = false
    current_review = YswsReviewService.fetch_review(review_id)

    ship_cert = current_review["shipCert"] || {}
    ship_cert_id = ship_cert["id"].to_s

    if ship_cert_id.present? && current_review["updatedAt"].present?
      existing_record = fetch_existing_airtable_record(ship_cert_id)
      if existing_record && existing_record["synced_at"].present?
        if Time.parse(existing_record["synced_at"]) >= Time.parse(current_review["updatedAt"])
          return
        end
      end
    end

    devlogs = current_review["devlogs"] || []
    total_approved_minutes = calculate_total_approved_minutes(devlogs) || 0

    if total_approved_minutes < 5
      @rejected_project = true
      Rails.logger.info "[YswsReviewSyncJob] review #{review_id} - only #{total_approved_minutes} approved minutes (< 5), marking as rejected"
    end

    code_url = ship_cert["repoUrl"]
    ft_project_id = ship_cert["ftProjectId"]

    # Check if project already exists in unified database             111 not implemented 110 implemented 101 implemented 100 implemented
    if code_url.present?
      existing_flavortown_record = find_project_in_unified_db_with_flavortown(code_url)

      if existing_flavortown_record
        existing_hours = existing_flavortown_record["Override Hours Spent"].to_f
        new_hours = (total_approved_minutes / 60.0).round(2)

        if new_hours > (existing_hours + 0.5)
          # Rails.logger.info "[YswsReviewSyncJob] Review #{review_id}: project exists in unified database under Flavortown with #{existing_hours}h, new review has #{new_hours}h (greater)"
          update_existing_record_unified_db(current_review, existing_flavortown_record, existing_hours, new_hours)  # will update the record in the unified db.
          # Continue to upsert to Airtable with in_unified_db flag
        else
          # Rails.logger.info "[YswsReviewSyncJob] Review #{review_id}: project exists in unified database under Flavortown with #{existing_hours}h, new review has #{new_hours}h (less or equal) - will still upsert to Airtable"
          # Continue to upsert to Airtable with in_unified_db flag
        end
      elsif project_exists_in_unified_db?(code_url)
        unified_db_hours = unified_db_hours_for_project(code_url)
        new_hours = (total_approved_minutes / 60.0).round(2)

        if new_hours > (unified_db_hours.to_f + 0.5)
          adjusted_hours = (new_hours - unified_db_hours.to_f).round(2)
          # Rails.logger.info "[YswsReviewSyncJob] Review #{review_id}: project exists in unified database (non-Flavortown) with #{unified_db_hours}h, new review has #{new_hours}h - using adjusted hours: #{adjusted_hours}h"
        else
          # Rails.logger.info "[YswsReviewSyncJob] Review #{review_id}: project exists in unified database (non-Flavortown) with #{unified_db_hours}h, new review has #{new_hours}h (less or equal) - will still upsert to Airtable"
          # Continue to upsert to Airtable with in_unified_db flag
        end
      end
    else
      Rails.logger.info "[YswsReviewSyncJob] SKIPPING: review #{review_id} - missing code URL"
      return
    end

    slack_id = ship_cert["ftSlackId"]

    return if slack_id.blank?

    user = User.find_by(slack_id: slack_id)
    return if user.nil?

    approved_orders = user.shop_orders
      .where(aasm_state: "fulfilled")
      .where("fulfilled_by IS NULL OR fulfilled_by NOT LIKE ?", "System%")
      .includes(:shop_item)

    hours_spent = adjusted_hours || (total_approved_minutes / 60.0)
    user_pii = extract_user_pii(user)
    if user.banned?
      @rejected_project = true
      report_status = "banned"
    else
      report_status = ""
    end
    create_airtable_record(current_review, report_status, user_pii, approved_orders, adjusted_hours: adjusted_hours)
  end

  def extract_user_pii(user)
    addresses = user.addresses

    {
      slack_id: user.slack_id,
      email: user.email,
      first_name: user.first_name,
      last_name: user.last_name,
      display_name: user.display_name,
      addresses: addresses,
      birthday: user.birthday
    }
  end

  def update_justification(current_review, old_hours, new_hours)
      <<~UPDATE_JUSTIFICATION
        ===== Project Updated =====
        #{old_hours} -> #{new_hours} hours
        A new Guardians of Integrity review and Ship Cert has been submitted for this project.
        The new review can be found at https://review.hackclub.com/admin/ysws_reviews/#{current_review["id"]}
      UPDATE_JUSTIFICATION
  end

  def update_existing_record_unified_db(current_review, existing_flavortown_record, existing_hours, new_hours)
    existing_flavortown_record["Override Hours Spent"] = new_hours
    existing_flavortown_record["Override Hours Spent Justification"] = existing_flavortown_record["Override Hours Spent Justification"].to_s + update_justification(current_review, existing_hours, new_hours)
    existing_flavortown_record.save
  end

  def create_airtable_record(review, report_status, user_pii, approved_orders, adjusted_hours: nil)
    ship_cert = review["shipCert"] || {}
    ship_cert_id = ship_cert["id"].to_s
    fields = build_record_fields(review, report_status, user_pii, approved_orders, adjusted_hours: adjusted_hours)

    # Rails.logger.info "[YswsReviewSyncJob] Upserting Airtable record for ship_cert_id #{ship_cert_id}"
    table.upsert(fields, "ship_cert_id")
  end

  def build_record_fields(review, report_status, user_pii, approved_orders, adjusted_hours: nil)
    ship_cert = review["shipCert"] || {}
    primary_address = user_pii[:addresses]&.first || {}
    devlogs = review["devlogs"] || []
    banner_url = banner_url_for_project_id(ship_cert["ftProjectId"])
    video_thumbnail_url = video_thumbnail_url_for_proof_video(ship_cert["proofVideoUrl"], ship_cert_id: ship_cert["id"].to_s)
    hours_spent = adjusted_hours || (calculate_total_approved_minutes(devlogs) / 60.0).round(2)

    if report_status == ""
      if project_has_pending_reports?(ship_cert["ftProjectId"])
        report_status = "pending_reports"
      end
    end

    {
      "review_id" => review["id"].to_s,
      "slack_id" => user_pii[:slack_id],
      "Email" => user_pii[:email],
      "First Name" => user_pii[:first_name],
      "Last Name" => user_pii[:last_name],
      "display_name" => user_pii[:display_name],
      "Address (Line 1)" => primary_address["line_1"],
      "Address (Line 2)" => primary_address["line_2"],
      "City" => primary_address["city"],
      "State / Province" => primary_address["state"],
      "ZIP / Postal Code" => primary_address["postal_code"],
      "Country" => primary_address["country"],
      "Birthday" => user_pii[:birthday],
      "ship_cert_id" => ship_cert["id"].to_s,
      "status" => review["status"],
      "synced_at" => Time.current.iso8601,
      "reviewer" => review.dig("reviewer", "username"),
      "Code URL" => ship_cert["repoUrl"],
      "Playable URL" => ship_cert["demoUrl"],
      "project_readme" => ship_cert["readmeUrl"],
      "Screenshot" => [
        banner_url.present? ? { "url" => banner_url } : (ship_cert["screenshotUrl"].present? ? { "url" => ship_cert["screenshotUrl"] } : nil),
        video_thumbnail_url.present? ? { "url" => video_thumbnail_url } : nil
      ].compact,
      "proof_video" => ship_cert["proofVideoUrl"].present? ? [ { "url" => ship_cert["proofVideoUrl"] } ] : nil,
      "Description" => ship_cert["description"],
      "Optional - Override Hours Spent" => hours_spent,
      "Optional - Override Hours Spent Justification" => adjusted_hours ? "Project Updated: #{build_justification(review, devlogs, approved_orders)}" : build_justification(review, devlogs, approved_orders),
      "in_unified_db" => project_exists_in_unified_db?(ship_cert["repoUrl"]),
      "rejected_project" => @rejected_project || false,
      "report_status" => report_status
    }
  end

  def calculate_total_approved_minutes(devlogs)
    return nil if devlogs.empty?

    devlogs.sum { |d| d["approvedMins"].to_i }
  end

  def build_justification(review, devlogs, approved_orders)
    return nil if devlogs.empty?

    ship_cert = review["shipCert"] || {}
    reviewer_username = review.dig("reviewer", "username") || "Unknown"
    ship_certifier = ship_cert.dig("reviewer", "username") || "a ship certifier"
    project_id = ship_cert["ftProjectId"]
    review_id = review["id"]
    ship_cert_id = ship_cert["id"]

    total_original_seconds = devlogs.sum { |d| d["origSecs"].to_i }
    total_original_minutes = total_original_seconds / 60
    total_hours = total_original_minutes / 60
    original_time_remaining_minutes = total_original_minutes % 60
    original_time_formatted = total_hours > 0 ? "#{total_hours}h #{original_time_remaining_minutes}min" : "#{original_time_remaining_minutes}min"

    total_approved_minutes = devlogs.sum { |d| d["approvedMins"].to_i }
    approved_hours = total_approved_minutes / 60
    approved_time_remaining_minutes = total_approved_minutes % 60
    approved_time_formatted = approved_hours > 0 ? "#{approved_hours}h #{approved_time_remaining_minutes}min" : "#{approved_time_remaining_minutes}min"

    selected_devlogs = devlogs.count > 4 ? [ devlogs.first ] + devlogs.last(3) : devlogs
    devlog_list = selected_devlogs.map do |d|
      title = d["title"].presence || "devlog ##{d['id']}"
      approved = d["approvedMins"].to_i
      "#{title}: #{approved} mins"
    end.join("\n")
    devlog_list += "\nand #{devlogs.count - 4} more devlogs." if devlogs.count > 4

    orders_section = build_orders_section(approved_orders)

    <<~JUSTIFICATION
      The user logged #{original_time_formatted} on hackatime. #{total_original_minutes == total_approved_minutes ? "" : "(This was adjusted to #{approved_time_formatted} after review.)"}

      The flavortown project can be found at https://flavortown.hackclub.com/projects/#{project_id}

      In this time they wrote #{devlogs.count} devlogs.

      This project was initially ship certified by #{ship_certifier}.

      Following this it was reviewed by the Guardian of Integrity, #{reviewer_username}.

      #{reviewer_username} approved:

      #{devlog_list}
      ====================================================
      The Full Integrity report + devlogs are at https://review.hackclub.com/admin/ysws_reviews/#{review_id}

      The Ship Cert is at https://review.hackclub.com/admin/ship_certifications/#{ship_cert_id}/edit
      ====================================================
      #{orders_section}
    JUSTIFICATION
  end

  def build_orders_section(approved_orders)
    manual_orders = approved_orders.reject { |order| order.fulfilled_by&.start_with?("System") }
    return "" if manual_orders.empty?

    orders_list = manual_orders.last(2).map do |order|
      item_name = order.shop_item.name
      fulfilled_by = order.fulfilled_by.presence || "Unknown"
      fulfilled_at = order.fulfilled_at&.strftime("%Y-%m-%d") || "Unknown date"
      "#{item_name} (x#{order.quantity}) - approved by #{fulfilled_by} on #{fulfilled_at}"
    end.join("\n")

    <<~ORDERS
      This user has the following manually approved shop orders:
      #{orders_list}
    ORDERS
  end

  def table
    @table ||= Norairrecord.table(
      airtable_api_key,
      airtable_base_id,
      table_name
    )
  end

  def table_name
    Rails.application.credentials.dig(:ysws_review, :airtable_table_name) ||
      ENV["YSWS_REVIEW_AIRTABLE_TABLE"] ||
      "YSWS Project Submission"
  end

  def airtable_api_key
    Rails.application.credentials.dig(:ysws_review, :airtable_api_key) ||
      Rails.application.credentials&.airtable&.api_key ||
      ENV["AIRTABLE_API_KEY"]
  end

  def airtable_base_id
    Rails.application.credentials.dig(:ysws_review, :airtable_base_id) ||
      ENV["YSWS_REVIEW_AIRTABLE_BASE_ID"]
  end

  def banner_url_for_project_id(ft_project_id)
    # Rails.logger.info("[YswsReviewSyncJob] banner_url_for_project_id: start ft_project_id=#{ft_project_id.inspect} (class=#{ft_project_id.class})")

    if ft_project_id.blank?
      # Rails.logger.warn("[YswsReviewSyncJob] banner_url_for_project_id: ft_project_id is blank")
      return nil
    end

    project = Project.find_by(id: ft_project_id)
    if project.nil?
      @rejected_project = true
      # Rails.logger.warn("[YswsReviewSyncJob] banner_url_for_project_id: Project not found by id=#{ft_project_id.inspect}")
      return nil
    end

    unless project.banner.attached?
      # Rails.logger.warn("[YswsReviewSyncJob] banner_url_for_project_id: Project #{project.id} has no banner attached")
      return nil
    end

    host = default_url_host
    if host.blank?
      # Rails.logger.error("[YswsReviewSyncJob] banner_url_for_project_id: host missing. action_mailer=#{Rails.application.config.action_mailer.default_url_options.inspect} routes=#{Rails.application.routes.default_url_options.inspect} ENV[APP_HOST]=#{ENV['APP_HOST'].inspect}")
      return nil
    end

    url = rails_blob_url(project.banner, host: host)
    # Rails.logger.info("[YswsReviewSyncJob] banner_url_for_project_id: success project_id=#{project.id} url=#{url}")
    url
  rescue StandardError => e
    # Rails.logger.error("[YswsReviewSyncJob] banner_url_for_project_id: exception project_id=#{ft_project_id.inspect} #{e.class}: #{e.message}")
    nil
  end

  def video_thumbnail_url_for_proof_video(proof_video_url, ship_cert_id: nil)
    return nil if proof_video_url.blank?

    # Check if existing record already has 2 screenshots in Airtable
    if ship_cert_id.present?
      existing_record = fetch_existing_airtable_record(ship_cert_id)
      screenshots = existing_record && existing_record["Screenshot"]

      if screenshots.present? && screenshots.count >= 2
        # Reuse the existing video thumbnail URL to avoid oscillating the Screenshot array
        first_screenshot = screenshots.first
        existing_thumbnail_url =
          if first_screenshot.is_a?(Hash)
            first_screenshot["url"]
          else
            first_screenshot
          end

        if existing_thumbnail_url.present?
          # Rails.logger.info("[YswsReviewSyncJob] video_thumbnail_url_for_proof_video: skipping ffmpeg - record already has #{screenshots.count} screenshots, reusing existing thumbnail #{existing_thumbnail_url.inspect}")
          return existing_thumbnail_url
        else
          # Rails.logger.info("[YswsReviewSyncJob] video_thumbnail_url_for_proof_video: skipping ffmpeg - record already has #{screenshots.count} screenshots but no reusable thumbnail URL found")
          return nil
        end
      end
    end

    host = default_url_host
    return nil if host.blank?

    # Rails.logger.info("[YswsReviewSyncJob] video_thumbnail_url_for_proof_video: downloading #{proof_video_url.inspect}")

    uri = URI(proof_video_url)
    raise ArgumentError, "Only HTTP(S) URLs are allowed" unless uri.is_a?(URI::HTTP)

    ext = File.extname(uri.path).downcase.presence || ".mp4"

    video_tmp = Tempfile.new([ "proof_video", ext ])
    video_tmp.binmode
    uri.open("rb") { |remote| IO.copy_stream(remote, video_tmp) }
    video_tmp.rewind

    # Get duration via ffprobe so we can seek to 2/5 of the way through (midpoint of 1/5–3/5)
    duration_str, = Open3.capture2(
      "ffprobe", "-v", "error",
      "-show_entries", "format=duration",
      "-of", "default=noprint_wrappers=1:nokey=1",
      video_tmp.path
    )
    duration = duration_str.strip.to_f
    seek_time = (duration > 0 ? duration * 0.4 : 1.0).round(3)
    # Rails.logger.info("[YswsReviewSyncJob] video_thumbnail_url_for_proof_video: duration=#{duration}s seek=#{seek_time}s")

    thumbnail_tmp = Tempfile.new([ "video_thumbnail", ".jpg" ])

    system(
      "ffmpeg", "-ss", seek_time.to_s,
      "-i", video_tmp.path,
      "-frames:v", "1",
      "-q:v", "2",
      thumbnail_tmp.path, "-y",
      exception: true
    )

    blob = ActiveStorage::Blob.create_and_upload!(
      io: File.open(thumbnail_tmp.path),
      filename: "video_thumbnail.jpg",
      content_type: "image/jpeg"
    )

    url = rails_blob_url(blob, host: host)
    # Rails.logger.info("[YswsReviewSyncJob] video_thumbnail_url_for_proof_video: success url=#{url}")
    url
  rescue StandardError => e
    # Rails.logger.error("[YswsReviewSyncJob] video_thumbnail_url_for_proof_video: #{e.class}: #{e.message}")
    nil
  ensure
    video_tmp&.close
    video_tmp&.unlink
    thumbnail_tmp&.close
    thumbnail_tmp&.unlink
  end

  def default_url_host
    ENV["APP_HOST"]
  end

  def get_formatted_code_url(code_url)
    return nil if code_url.blank?
    code_url.sub(%r{^https?://}, "").sub(%r{(?:\.git)?/?(?:#.*)?$}, "")
  end

  def project_exists_in_unified_db?(code_url)
    formatted_url = get_formatted_code_url(code_url)
    unified_db_table.all(
      filter: "AND(FIND('#{formatted_url}', {Code URL}) > 0, NOT({YSWS} = 'Flavortown'))"
    ).any?
  end

  def unified_db_hours_for_project(code_url)
    formatted_url = get_formatted_code_url(code_url)
    record = unified_db_table.all(
      filter: "AND(FIND('#{formatted_url}', {Code URL}) > 0, NOT({YSWS} = 'Flavortown'))"
    ).first
    record&.[]("Hours Spent")&.to_f
  end

  def find_project_in_unified_db_with_flavortown(code_url)
    formatted_url = get_formatted_code_url(code_url)
    unified_db_table.all(
      filter: "AND(FIND('#{formatted_url}', {Code URL}) > 0, {YSWS} = 'Flavortown')"
    ).first
  end

  def unified_db_table
    @unified_db_table ||= Norairrecord.table(
      ENV["UNIFIED_DB_INTEGRATION_AIRTABLE_KEY"],
      "app3A5kJwYqxMLOgh",
      "Approved Projects"
    )
  end

  def project_has_pending_reports?(ft_project_id)
    return false if ft_project_id.blank?
    Project::Report.where(project_id: ft_project_id, status: [ :pending ]).exists?
  end

  def fetch_existing_airtable_record(ship_cert_id)
    return nil if ship_cert_id.blank?

    table.all(filter: "{ship_cert_id} = '#{ship_cert_id}'").first
  rescue StandardError => e
    # Rails.logger.error("[YswsReviewSyncJob] fetch_existing_airtable_record: #{e.class}: #{e.message}")
    nil
  end
end
