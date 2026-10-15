module ExternalDashboard
  class CertIdBackfillService
    APPROVED_PATH = "/api/v1/certifications/approved".freeze
    TIMEOUT_SECONDS = 30

    Result = Struct.new(:status, :total, :persisted, :skipped, :error, keyword_init: true)

    def self.call(refetch: true)
      new(refetch: refetch).call
    end

    def initialize(refetch:)
      @refetch = refetch
    end

    def call
      return Result.new(status: :not_configured, total: 0, persisted: 0, skipped: 0, error: Client::NOT_CONFIGURED_ERROR) unless Client.configured?

      response = Client.connection(timeout: TIMEOUT_SECONDS).get(APPROVED_PATH, refetch_param)
      return remote_error(response) unless response.status.between?(200, 299)

      certs = Array(Client.parse_json(response.body)["certifications"])
      persisted = 0
      skipped = 0

      certs.each do |cert|
        persist(cert) == :persisted ? persisted += 1 : skipped += 1
      end

      Rails.logger.info "[ExternalDashboard::CertIdBackfillService] total=#{certs.size} persisted=#{persisted} skipped=#{skipped}"
      Result.new(status: :ok, total: certs.size, persisted: persisted, skipped: skipped)
    end

    private

    def refetch_param
      @refetch ? { refetch: true } : {}
    end

    def persist(cert)
      external_id = cert["externalId"].to_s
      return :skipped unless external_id.match?(/\A\d+\z/)

      local_cert = Certification::Ship.find_by(id: external_id.to_i)
      return :skipped if local_cert.nil?

      local_cert.assign_external_certification_id!(cert["id"])
    end

    def remote_error(response)
      Rails.logger.warn "[ExternalDashboard::CertIdBackfillService] remote error http=#{response.status} body=#{response.body.to_s.truncate(Client::ERROR_MESSAGE_MAX)}"
      Result.new(status: :remote_error, total: 0, persisted: 0, skipped: 0, error: "http #{response.status}")
    end
  end
end
