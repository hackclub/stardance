module Admin
  class PollResultsController < Admin::ApplicationController
    def show
      authorize :admin, :index?
      return head :not_found unless Flipper.enabled?(:"justin-melena", current_user)
      @tally = PollVote.tally
    end
  end
end
