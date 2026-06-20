class ContributorsController < ApplicationController
  def index
    head :not_found and return unless Flipper.enabled?(:week_3_release, current_user)

    @contributors = GithubContributors.leaderboard
    @total_merged_prs = @contributors.sum { |contributor| contributor[:merged_pr_count] }
  end
end
