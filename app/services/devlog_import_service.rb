require "resolv"
require "ipaddr"

class DevlogImportService
  ALLOWED_HOSTS = %w[
    raw.githubusercontent.com
    github.com
    user-images.githubusercontent.com
    dl.airtableusercontent.com
    v5.airtableusercontent.com
  ].freeze

  ALLOWED_DOMAINS = %w[
    .hackclub.com
  ].freeze

  ALLOWED_CONTENT_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze
  MAX_IMAGE_SIZE = 50.megabytes

  MAGIC_BYTES = {
    "image/png" => "\x89PNG".b,
    "image/jpeg" => "\xFF\xD8\xFF".b,
    "image/gif" => "GIF".b,
    "image/webp" => "RIFF".b
  }.freeze

  EXTENSIONS = { "image/png" => ".png", "image/jpeg" => ".jpg", "image/webp" => ".webp", "image/gif" => ".gif" }.freeze

  Result = Struct.new(:success?, :devlogs, :errors, keyword_init: true)

  def initialize(json_string, dry_run: false)
    @entries = JSON.parse(json_string)
    @dry_run = dry_run
    @errors = []
    @created = []
  rescue JSON::ParserError => e
    @entries = nil
    @errors = [ "Invalid JSON: #{e.message}" ]
  end

  def call
    return failure if @entries.nil?
    return failure("JSON must be an array of objects") unless @entries.is_a?(Array) && @entries.all?(Hash)

    validate_entries
    return failure if @errors.any?
    return Result.new(success?: true, devlogs: [], errors: []) if @dry_run

    import_entries
  end

  private

  def failure(msg = nil)
    @errors << msg if msg
    Result.new(success?: false, devlogs: [], errors: @errors)
  end

  def validate_entries
    @entries.each_with_index do |entry, i|
      label = "Entry ##{i + 1}"
      %w[project_id body hours image].each { |f| @errors << "#{label}: missing '#{f}'" if entry[f].blank? }

      @errors << "#{label}: hours must be >= 0.25" if entry["hours"].present? && entry["hours"].to_f < 0.25
      @errors << "#{label}: phase must be 'design' or 'build'" if entry["phase"].present? && !Post::Devlog::PHASES.include?(entry["phase"])

      if entry["image"].present?
        uri = URI.parse(entry["image"]) rescue nil
        if uri.nil?
          @errors << "#{label}: invalid image URL"
        elsif !uri.is_a?(URI::HTTPS)
          @errors << "#{label}: image URL must be HTTPS"
        elsif !allowed_host?(uri.host)
          @errors << "#{label}: image host '#{uri.host}' not in allowlist"
        end
      end

      @errors << "#{label}: project #{entry['project_id']} not found" if entry["project_id"].present? && !Project.exists?(id: entry["project_id"])
    end
  end

  def import_entries
    ActiveRecord::Base.transaction do
      @entries.each_with_index do |entry, i|
        result = import_single(entry, "Entry ##{i + 1}")
        if result.is_a?(String)
          @errors << result
          raise ActiveRecord::Rollback
        end
        @created << result
      end
    end

    return failure if @errors.any?

    @created.map { |c| c[:project_id] }.uniq.each { |pid| Project.find(pid).recalculate_duration_seconds! }
    Result.new(success?: true, devlogs: @created, errors: [])
  end

  def import_single(entry, label)
    project = Project.find(entry["project_id"])
    user = project.memberships.find_by(role: :owner)&.user || project.memberships.first&.user
    return "#{label}: no user found for project #{project.id}" unless user

    image_data = download_image(entry["image"], label)
    return image_data if image_data.is_a?(String)

    devlog = Post::Devlog.new(
      body: entry["body"],
      duration_seconds: (entry["hours"].to_f * 3600).to_i,
      phase: entry["phase"].presence || project.hardware_stage,
      hackatime_projects_key_snapshot: "journal-import"
    )
    devlog.uploading_attachments = true
    devlog.save!
    devlog.attachments.attach(image_data)

    post = Post.create!(project: project, user: user, postable: devlog)

    if entry["created_at"].present?
      timestamp = Time.parse(entry["created_at"])
      devlog.update_columns(created_at: timestamp, updated_at: timestamp)
      post.update_columns(created_at: timestamp, updated_at: timestamp)
    end

    PaperTrail::Version.create!(
      item_type: "Post::Devlog", item_id: devlog.id,
      event: "journal_import", whodunnit: user.id,
      object_changes: { source: "journal_import", hours: entry["hours"], image_url: entry["image"], created_at: entry["created_at"] }.to_yaml
    )

    { devlog_id: devlog.id, post_id: post.id, hours: entry["hours"], project_id: project.id }
  end

  MAX_REDIRECTS = 5

  def download_image(url, label)
    uri = URI.parse(url)
    response = follow_redirects(uri)

    return "#{label}: failed to download image (HTTP #{response.code})" unless response.is_a?(Net::HTTPSuccess)
    return "#{label}: image too large (#{response.body.bytesize} bytes)" if response.body.bytesize > MAX_IMAGE_SIZE

    content_type = response["content-type"]&.split(";")&.first&.strip
    detected_type = MAGIC_BYTES.find { |_, magic| response.body.byteslice(0, magic.length) == magic }&.first
    return "#{label}: file magic bytes don't match any supported image format" unless detected_type

    if content_type.nil? || content_type == "application/octet-stream"
      content_type = detected_type
    elsif !ALLOWED_CONTENT_TYPES.include?(content_type)
      return "#{label}: disallowed content type '#{content_type}'"
    elsif detected_type != content_type
      return "#{label}: content type mismatch (header: #{content_type}, magic: #{detected_type})"
    end

    tempfile = Tempfile.new([ "devlog-import", EXTENSIONS[content_type] || ".bin" ])
    tempfile.binmode
    tempfile.write(response.body)
    tempfile.rewind

    { io: tempfile, filename: File.basename(uri.path).presence || "image#{EXTENSIONS[content_type]}", content_type: content_type }
  rescue => e
    "#{label}: image download error: #{e.message}"
  end

  def follow_redirects(uri, limit = MAX_REDIRECTS)
    raise "too many redirects" if limit == 0
    raise "redirect to non-HTTPS URL" unless uri.is_a?(URI::HTTPS)
    assert_public_host!(uri.host)

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
      http.request(Net::HTTP::Get.new(uri))
    end

    if response.is_a?(Net::HTTPRedirection) && response["location"]
      follow_redirects(URI.parse(response["location"]), limit - 1)
    else
      response
    end
  end

  def allowed_host?(host)
    ALLOWED_HOSTS.include?(host) || ALLOWED_DOMAINS.any? { |domain| host.end_with?(domain) }
  end

  def assert_public_host!(hostname)
    addrs = Resolv.getaddresses(hostname)
    raise "could not resolve host '#{hostname}'" if addrs.empty?

    addrs.each do |addr_str|
      ip = IPAddr.new(addr_str)
      if ip.private? || ip.loopback? || ip.link_local?
        raise "redirect to private/internal address blocked (#{hostname} -> #{addr_str})"
      end
    end
  end
end
