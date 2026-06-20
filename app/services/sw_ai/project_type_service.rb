# frozen_string_literal: true

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

      response = connection(api_key).post(ENDPOINT) do |req|
        req.body = payload
      end

      if response.success?
        type = response.body["type"].presence
        Result.new(type: (type == "Unknown" ? nil : type), ok: true)
      else
        Rails.logger.warn "[SwAi::ProjectTypeService] HTTP #{response.status} for project #{@project.id}"
        Result.new(type: nil, ok: false)
      end
    rescue => e
      Rails.logger.error "[SwAi::ProjectTypeService] #{e.class}: #{e.message} for project #{@project.id}"
      raise
    end

    private

    def connection(api_key)
      base = Rails.application.config.x.sw_ai.url.chomp("/")
      Faraday.new(url: base) do |conn|
        conn.request  :json
        conn.response :json
        conn.headers["X-API-Key"] = api_key
        conn.options.open_timeout = TIMEOUT
        conn.options.timeout      = TIMEOUT
      end
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
