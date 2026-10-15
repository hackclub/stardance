class User::RefreshVerdictsJob < ApplicationJob
  queue_as :literally_whenever

  def perform
    Secrets::VoteVerdictRefresh.call
  end
end
