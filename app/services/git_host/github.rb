module GitHost
  class Github < Base
    PROXY_BASE = "https://gh-proxy.hackclub.com/gh".freeze
    DIRECT_API_BASE = "https://api.github.com".freeze

    def self.handles?(url)
      url.match?(%r{github\.com/[^/]+/[^/]+})
    end

    def provider_name
      "github"
    end

    def provider_display_name
      "GitHub"
    end

    def fetch_commits(since: nil, per_page: 100)
      return [] unless owner && repo

      all_commits = []
      page = 1

      loop do
        path = "repos/#{owner}/#{repo}/commits"
        params = { per_page: per_page, page: page }
        params[:since] = since.iso8601 if since

        full_url = "#{api_base}/#{path}?#{params.to_query}"
        commits = http_get(full_url, headers: auth_headers)

        break unless commits.is_a?(Array) && commits.any?

        all_commits.concat(commits.map { |c| normalize_commit(c) })

        break if commits.size < per_page

        page += 1
      end

      all_commits
    end

    protected

    def parse_url!
      match = repo_url.match(%r{github\.com/([^/]+)/([^/]+?)(?:\.git)?(?:/|$)})
      return unless match

      @owner = match[1]
      @repo = match[2].sub(/\.git$/, "")
    end

    def normalize_commit(raw)
      commit_data = raw["commit"] || {}
      author = commit_data["author"] || {}
      stats = raw["stats"] || {}

      {
        sha: raw["sha"],
        message: commit_data["message"],
        author_name: author["name"],
        author_email: author["email"],
        authored_at: author["date"] ? Time.parse(author["date"]) : nil,
        url: raw["html_url"],
        additions: stats["additions"],
        deletions: stats["deletions"],
        files_changed: raw["files"]&.size
      }
    end

    private

    def use_proxy?
      ENV["GH_PROXY_API_KEY"].present?
    end

    def api_base
      use_proxy? ? PROXY_BASE : DIRECT_API_BASE
    end

    def auth_headers
      if use_proxy?
        { "X-API-Key" => ENV["GH_PROXY_API_KEY"] }
      else
        token = ENV["GITHUB_ACCESS_TOKEN"]
        return {} unless token

        { "Authorization" => "Bearer #{token}" }
      end
    end
  end
end
