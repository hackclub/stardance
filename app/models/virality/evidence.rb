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

    def self.qualifies?(platform:, metric_name:, metric_value:, tier:)
      threshold = THRESHOLDS.dig(platform, metric_name, tier == "great" ? 1 : 0)
      threshold.present? && metric_value.to_i >= threshold
    end
  end
end
