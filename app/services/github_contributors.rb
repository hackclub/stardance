class GithubContributors
  REPO_URL = "https://github.com/hackclub/stardance"
  CACHE_KEY = "github_contributors/merged_pr_counts/v1"
  CACHE_TTL = 1.hour

  class << self
    def leaderboard
      Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) do
        build_leaderboard(GitHost::Github.new(REPO_URL).fetch_merged_pulls)
      end
    end

    def build_leaderboard(pulls)
      pulls
        .reject { |pull| pull[:author_login].end_with?("[bot]") }
        .group_by { |pull| pull[:author_login] }
        .map do |login, authored|
          {
            login: login,
            avatar_url: authored.first[:author_avatar_url],
            url: authored.first[:author_url],
            merged_pr_count: authored.size
          }
        end
        .sort_by { |contributor| [ -contributor[:merged_pr_count], contributor[:login].downcase ] }
    end
  end
end
