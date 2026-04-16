module GitHost
  class Base
    attr_reader :repo_url, :owner, :repo

    def initialize(repo_url)
      @repo_url = repo_url
      parse_url!
    end

    def self.for(repo_url)
      return nil if repo_url.blank?

      provider_class = [
        GitHost::Github,
        GitHost::GitCli
      ].find { |klass| klass.handles?(repo_url) }

      provider_class&.new(repo_url)
    end

    def self.handles?(url)
      raise NotImplementedError
    end

    def fetch_commits(since: nil, per_page: 100)
      raise NotImplementedError
    end

    def provider_name
      raise NotImplementedError
    end

    protected

    def parse_url!
      raise NotImplementedError
    end

    def normalize_commit(raw_commit)
      raise NotImplementedError
    end

    def http_get(url, headers: {})
      response = Faraday.get(url) do |req|
        req.headers["Accept"] = "application/json"
        req.headers["User-Agent"] = "Stardance/1.0"
        headers.each { |k, v| req.headers[k] = v }
      end

      return nil unless response.success?

      JSON.parse(response.body)
    rescue JSON::ParserError, Faraday::Error => e
      Rails.logger.error("GitHost request failed: #{e.message}")
      nil
    end
  end
end
