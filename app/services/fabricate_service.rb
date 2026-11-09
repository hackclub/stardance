# Hands a design-stage hardware project to Fabricate (fabricate.hackclub.com),
# Hack Club's newest hardware program. The project, its owner's profile and the
# devlogs the owner posted go to Fabricate's /imports/stardance, signed with
# the secret both apps share. Fabricate makes the project (and the owner's
# account, if they're new there), answers with its id, and copies the devlog
# media from our Active Storage URLs in the background.
class FabricateService
  BASE_URL = Rails.application.credentials.dig(:fabricate, :base_url) || ENV.fetch("FABRICATE_BASE_URL", "https://fabricate.hackclub.com")
  # Where this server reaches Fabricate, when that differs from where browsers
  # do (a local Fabricate seen from inside Docker).
  API_URL = Rails.application.credentials.dig(:fabricate, :api_url) || ENV.fetch("FABRICATE_API_URL", BASE_URL)
  # How Fabricate works, linked from the "Move to Fabricate" popup.
  OVERVIEW_URL = "#{BASE_URL}/docs/overview".freeze

  OPEN_TIMEOUT = 3
  READ_TIMEOUT = 15

  class Error < StandardError; end

  class << self
    # Fabricate's id for the project it made from +project+. Sending the same
    # project again returns the same id, so a retry never makes a second one.
    def import_project!(project, owner:, host:)
      secret = import_secret
      raise Error, "FABRICATE_IMPORT_SECRET is not set" if secret.blank?

      body = payload(project, owner, host).to_json
      timestamp = Time.current.to_i.to_s
      response = connection.post("imports/stardance", body) do |req|
        req.headers["X-Stardance-Timestamp"] = timestamp
        req.headers["X-Stardance-Signature"] = "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body}")}"
      end
      raise Error, "Fabricate answered #{response.status}: #{response.body.to_s.first(200)}" unless response.success?

      JSON.parse(response.body).fetch("project_id")
    rescue Faraday::Error, JSON::ParserError, KeyError => e
      raise Error, e.message
    end

    # Fabricate asks whoever follows this to sign in with Hack Club first, so
    # the owner lands on the project as its owner.
    def project_url(fabricate_project_id) = "#{BASE_URL}/projects/#{fabricate_project_id}?from=stardance"

    private

    # The secret Fabricate checks the signature with (its STARDANCE_IMPORT_SECRET).
    def import_secret
      Rails.application.credentials.dig(:fabricate, :import_secret) || ENV.fetch("FABRICATE_IMPORT_SECRET", "")
    end

    def payload(project, owner, host)
      {
        project: {
          id: project.id,
          title: project.title,
          description: project.description,
          repo_url: project.repo_url,
          demo_url: project.demo_url,
          banner_url: (blob_url(project.banner, host) if project.banner.attached?),
          created_at: project.created_at.iso8601
        },
        owner: {
          hca_id: owner.hack_club_identity&.uid,
          email: owner.email,
          display_name: owner.display_name,
          bio: owner.bio
        },
        devlogs: owner_devlogs(project, owner).map do |devlog|
          {
            id: devlog.id,
            body: devlog.body,
            duration_seconds: devlog.duration_seconds,
            created_at: devlog.created_at.iso8601,
            media_urls: devlog.attachments.map { |attachment| blob_url(attachment, host) }
          }
        end
      }
    end

    # Fabricate projects have one maker, so teammates' devlogs stay behind.
    def owner_devlogs(project, owner)
      Post::Devlog.joins(:post)
                  .where(posts: { project_id: project.id, user_id: owner.id })
                  .includes(attachments_attachments: :blob)
                  .order(:created_at)
    end

    def blob_url(attachment, host)
      Rails.application.routes.url_helpers.rails_blob_url(attachment, host: host)
    end

    def connection
      Faraday.new(url: API_URL) do |conn|
        conn.options.open_timeout = OPEN_TIMEOUT
        conn.options.timeout = READ_TIMEOUT
        conn.headers["Content-Type"] = "application/json"
        conn.headers["User-Agent"] = Rails.application.config.user_agent
      end
    end
  end
end
