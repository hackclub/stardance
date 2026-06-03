# frozen_string_literal: true

require "net/http"

module SwAi
  class ProjectTypeService
    ENDPOINT = "/projects/type"
    TIMEOUT   = 30

    Result = Data.define(:type, :ok)

    def initialize(project)
      @project = project
    end

    def call
      api_key = Rails.application.config.x.sw_ai.api_key
      return Result.new(type: nil, ok: false) if api_key.blank?

      base = Rails.application.config.x.sw_ai.url.chomp("/")
      uri  = URI("#{base}#{ENDPOINT}")

      response = post(uri, api_key)

      if response.is_a?(Net::HTTPSuccess)
        parsed = JSON.parse(response.body)
        type   = parsed["type"].presence
        Result.new(type: (type == "Unknown" ? nil : type), ok: true)
      else
        Rails.logger.warn "[SwAi::ProjectTypeService] HTTP #{response.code} for project #{@project.id}"
        Result.new(type: nil, ok: false)
      end
    rescue => e
      Rails.logger.error "[SwAi::ProjectTypeService] #{e.class}: #{e.message} for project #{@project.id}"
      raise
    end

    private

    def post(uri, api_key)
      http              = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = uri.scheme == "https"
      http.open_timeout = TIMEOUT
      http.read_timeout = TIMEOUT

      req                  = Net::HTTP::Post.new(uri.path)
      req["Content-Type"]  = "application/json"
      req["X-API-Key"]     = api_key
      req.body             = payload.to_json

      http.request(req)
    end

    def payload
      {
        title:     @project.title.to_s,
        desc:      @project.description.to_s,
        readmeUrl: @project.readme_url.to_s,
        demoUrl:   @project.demo_url.to_s,
        repoUrl:   @project.repo_url.to_s
      }
    end
  end
end
