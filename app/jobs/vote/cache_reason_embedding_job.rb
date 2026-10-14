class Vote::CacheReasonEmbeddingJob < ApplicationJob
  queue_as :literally_whenever

  def perform(vote_id)
    vote_reason_embedder = "Secrets::VoteReasonEmbedder".safe_constantize
    return unless vote_reason_embedder

    vote = Vote.includes(:project).find_by(id: vote_id)
    return if vote.nil? || vote.reason.blank?

    vote_reason_embedder.call(vote: vote)
  end
end
