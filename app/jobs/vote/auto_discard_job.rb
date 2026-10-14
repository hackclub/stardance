class Vote::AutoDiscardJob < ApplicationJob
  queue_as :literally_whenever

  def perform(vote_id)
    vote_auto_discarder = "Secrets::VoteAutoDiscarder".safe_constantize
    return unless vote_auto_discarder

    vote = Vote.includes(:project, :assignment, :events).find_by(id: vote_id)
    return if vote.nil? || vote.discarded?

    vote_auto_discarder.call(vote: vote)
    return if vote.discarded?

    vote.update!(auto_discard_checked_at: Time.current)
    ShipEventPayoutRefreshJob.perform_later(vote.ship_event_id)
  end
end
