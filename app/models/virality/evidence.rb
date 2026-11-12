module Virality
  class Evidence
    # Each metric has its own Good / Great threshold. A submission may qualify
    # through any one metric; impressions are not interchangeable with likes.
    THRESHOLDS = {
      "Reddit" => { "upvotes" => [ 25, 500 ] },
      "Hacker News" => { "points" => [ 10, 100 ] },
      "GitHub" => { "stars" => [ 25, 100 ] },
      "YouTube" => { "views" => [ 250, 50_000 ] },
      "TikTok / Reels / Shorts" => { "views" => [ 5_000, 100_000 ] },
      "Twitter / X" => { "likes" => [ 50, 1_500 ] },
      "Bluesky / Threads" => { "likes" => [ 50, 1_500 ] },
      "Instagram" => { "likes" => [ 200, 10_000 ], "views" => [ nil, 100_000 ] },
      "App store" => { "downloads" => [ 100, 10_000 ] },
      "Package manager" => { "downloads" => [ 1_000, 50_000 ] },
      "Modrinth / CurseForge" => { "downloads" => [ 2_500, 100_000 ] },
      "Blog / news article" => { "feature" => [ 1, nil ] },
      "Other" => {}
    }.freeze

    SHORT_VIDEO = "TikTok / Reels / Shorts".freeze
    HOSTS = {
      "reddit.com" => "Reddit",
      "news.ycombinator.com" => "Hacker News",
      "github.com" => "GitHub",
      "youtube.com" => "YouTube",
      "youtu.be" => "YouTube",
      "tiktok.com" => SHORT_VIDEO,
      "twitter.com" => "Twitter / X",
      "x.com" => "Twitter / X",
      "bsky.app" => "Bluesky / Threads",
      "threads.net" => "Bluesky / Threads",
      "threads.com" => "Bluesky / Threads",
      "instagram.com" => "Instagram",
      "apps.apple.com" => "App store",
      "play.google.com" => "App store",
      "npmjs.com" => "Package manager",
      "pypi.org" => "Package manager",
      "crates.io" => "Package manager",
      "rubygems.org" => "Package manager",
      "modrinth.com" => "Modrinth / CurseForge",
      "curseforge.com" => "Modrinth / CurseForge"
    }.freeze

    # Best guess at the platform for an evidence link, so reviewers rarely
    # have to pick it by hand.
    def self.platform_for(url)
      uri = URI.parse(url.to_s)
      return SHORT_VIDEO if uri.path.to_s.match?(%r{\A/(shorts|reels?)/})

      host = uri.host.to_s.downcase
      HOSTS.find { |domain, _| host == domain || host.end_with?(".#{domain}") }&.last
    rescue URI::InvalidURIError
      nil
    end

    def self.qualifies?(platform:, metric_name:, metric_value:, tier:)
      threshold = THRESHOLDS.dig(platform, metric_name, tier == "great" ? 1 : 0)
      threshold.present? && metric_value.to_i >= threshold
    end
  end
end
