class ContributorsController < ApplicationController
  def index
    @contributors = GithubContributors.leaderboard
    @total_merged_prs = @contributors.sum { |contributor| contributor[:merged_pr_count] }
  end
end
