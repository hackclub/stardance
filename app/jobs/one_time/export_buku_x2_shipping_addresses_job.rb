require "csv"

class OneTime::ExportBukuX2ShippingAddressesJob < ApplicationJob
  class ExportError < StandardError; end

  self.log_arguments = false
  before_enqueue { raise ExportError, "Run synchronously with perform_now; files are local to the runner" }

  ADDRESS_FIELDS = %w[first_name last_name line_1 line_2 city state postal_code country].freeze
  HEADERS = %w[user_id email status address_count] + ADDRESS_FIELDS
  THROTTLE_SECONDS = 0.2
  MAX_INPUT_BYTES = 5.megabytes

  # Nothing is scheduled automatically. Only paths enter Active Job; participant
  # data stays in private files, never job arguments, log messages or DB writes.
  def perform(input_path:, output_path:, dry_run: true)
    raise ExportError, "dry_run must be true or false" unless [ true, false ].include?(dry_run)

    ids = read_participants(input_path)
    output_path = private_output_path(output_path)
    counts = Hash.new(0)

    File.open(output_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
      csv = CSV.new(file)
      csv << HEADERS
      ids.uniq.each do |id|
        result = export_participant(id, dry_run: dry_run)
        counts[result.fetch("status")] += 1
        csv << HEADERS.map { |key| safe_cell(result[key]) }
        file.flush
      end
    end

    summary = { input_rows: ids.size, unique_users: ids.uniq.size, duplicate_rows: ids.size - ids.uniq.size,
                dry_run: dry_run, counts: counts }
    Rails.logger.info("[BukuX2ShippingExport] completed job_id=#{job_id} #{summary.to_json}")
    summary
  rescue ExportError
    raise
  rescue StandardError
    # CSV/HTTP/filesystem exceptions can contain input values. Do not forward
    # their messages or causes to ApplicationJob's Sentry handler.
    raise ExportError, "Export failed; any output file is incomplete. Check private files and rerun to a new path", cause: nil
  end

  private
    def read_participants(path)
      input = File.realpath(path)
      validate_private_directory!(File.dirname(input))
      stat = File.stat(input)
      unless stat.file? && stat.owned? && (stat.mode & 0o077).zero? && stat.size <= MAX_INPUT_BYTES
        raise ExportError, "Input must be an owner-only regular file of at most 5 MB"
      end

      table = CSV.read(input, headers: true, encoding: "bom|utf-8")
      unless table.headers.count("user_id") == 1 && table.headers.none?(&:blank?) && table.headers.uniq.size == table.headers.size
        raise ExportError, "CSV needs one user_id column and unique nonblank headers"
      end
      raise ExportError, "CSV has no participants" if table.empty?

      table.map do |row|
        id = row["user_id"].to_s.strip
        unless row.headers.none?(nil) && id.match?(/\A[1-9]\d{0,18}\z/) && id.to_i <= 9_223_372_036_854_775_807
          raise ExportError, "CSV contains an invalid user_id or extra columns"
        end
        id.to_i
      end
    end

    def private_output_path(path)
      parent = File.realpath(File.dirname(path))
      validate_private_directory!(parent)
      File.join(parent, File.basename(path))
    end

    def validate_private_directory!(path)
      stat = File.stat(path)
      root = Rails.root.realpath.to_s
      if path == root || path.start_with?(root + "/") || !stat.directory? || !stat.owned? || (stat.mode & 0o077).positive?
        raise ExportError, "Use an owner-only directory (mode 700) outside the application checkout"
      end
    end

    def export_participant(id, dry_run:)
      result = { "user_id" => id }
      user = User.find_by(id: id)
      return result.merge("status" => "user_not_found") unless user

      result["email"] = user.email
      identity = user.hack_club_identity
      return result.merge("status" => "no_hca_identity") unless identity
      return result.merge("status" => "no_access_token") if identity.access_token.blank?
      return result.merge("status" => "ready") if dry_run

      result.merge(fetch_address(identity.access_token))
    end

    def fetch_address(token)
      response = HCAService.connection.get("/api/v1/me") do |request|
        request.headers["Authorization"] = "Bearer #{token}"
        request.headers["Accept"] = "application/json"
        request.options.open_timeout = 5
        request.options.timeout = 15
      end
      return { "status" => "http_#{response.status}" } unless response.success?

      body = JSON.parse(response.body)
      identity = body.is_a?(Hash) ? body["identity"] : nil
      return { "status" => "invalid_response" } unless identity.is_a?(Hash)
      return { "status" => "address_field_unavailable" } unless identity.key?("addresses")

      select_address(identity["addresses"])
    rescue Faraday::Error
      { "status" => "request_failed" }
    rescue JSON::ParserError
      { "status" => "invalid_response" }
    ensure
      sleep THROTTLE_SECONDS
    end

    def select_address(addresses)
      return { "status" => "no_address", "address_count" => 0 } if addresses.nil? || addresses == []
      return { "status" => "invalid_response" } unless addresses.is_a?(Array) && addresses.all? { |address| address.is_a?(Hash) }

      primary = addresses.select { |address| address["primary"] == true }
      address = primary.one? ? primary.first : (addresses.first if addresses.one?)
      result = { "address_count" => addresses.size }
      return result.merge("status" => "multiple_addresses") unless address
      return result.merge("status" => "invalid_response") unless ADDRESS_FIELDS.all? { |key| address[key].nil? || address[key].is_a?(String) }

      # Do not guess an address or export unrelated HCA profile fields.
      fields = address.slice(*ADDRESS_FIELDS)
      status = fields["line_1"].present? && fields["country"].present? ? "ok" : "incomplete_address"
      result.merge(fields).merge("status" => status)
    end

    def safe_cell(value)
      return value unless value.is_a?(String)

      value.match?(/\A(?:\s*[=+@-]|[\t\r\n])/) ? "'#{value}" : value
    end
end
