module ExternalDashboard
  class ReviewerPayoutBulkStatusProcessor
    def self.call
      new.call
    end

    def call
      requests_by_user = ::ReviewerPayoutRequest.includes(:admin).order(created_at: :desc).group_by(&:user_id)

      reviewers = User.where("'project_certifier' = ANY(granted_roles)")
                      .or(User.where(id: requests_by_user.keys))
                      .or(User.where(id: Certification::Ship.decided.select(:reviewer_id)))
                      .or(User.where(id: Certification::FundingRequest.decided.select(:reviewer_id)))
                      .order(:id)
                      .to_a
      balances = ::ReviewerPayoutRequest.available_to_request_by(reviewers.map(&:id))

      summaries = reviewers.map do |user|
        ReviewerPayoutSummary.new(user, requests_by_user.fetch(user.id, []), available_balance: balances.fetch(user.id))
      end

      { reviewers: summaries.map(&:as_json) }
    end
  end
end
