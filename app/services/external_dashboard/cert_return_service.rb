module ExternalDashboard
  class CertReturnService
    Result = Struct.new(:status, :http_status, :error, keyword_init: true)

    def self.call(cert)
      new(cert).call
    end

    def initialize(cert)
      @cert = cert
      @reason = cert.recert_reason.to_s.strip.truncate(Post::ShipEvent::RETURN_REASON_MAX_LENGTH, omission: "")
    end

    def call
      return Result.new(status: :not_configured, error: Client::NOT_CONFIGURED_ERROR) unless Client.configured?
      return Result.new(status: :skipped, error: "cert has no external_certification_id") if external_id.blank?
      return Result.new(status: :skipped, error: "reason is blank") if @reason.blank?

      response = Client.connection.post(path, { reason: @reason }.to_json)
      parse_response(response)
    end

    private

    def external_id
      @cert.external_certification_id.to_s
    end

    def path
      "/api/v1/certifications/#{external_id}/return"
    end

    def parse_response(response)
      error = Client.error_from(Client.parse_json(response.body))

      case response.status
      when 200..299
        Result.new(status: :ok, http_status: response.status)
      when 400..499
        Result.new(status: :client_error, http_status: response.status, error: error)
      else
        Result.new(status: :server_error, http_status: response.status, error: error)
      end
    end
  end
end
