class BroadcastVoteToChannelJob < ApplicationJob
  queue_as :latency_10s

  CHANNEL_ID = "C0AFB0JU00P"

  def perform(vote)
    user = vote.user

    SendSlackDmJob.perform_now(
      CHANNEL_ID,
      nil,
      blocks_path: "notifications/votes/broadcast",
      locals: {
        voter_name: user.display_name,
        voter_slack_id: user.slack_id,
        project_title: vote.project.title,
        project_url: "https://stardance.hackclub.com/projects/#{vote.project.id}",
        originality_score: vote.originality_score,
        technical_score: vote.technical_score,
        usability_score: vote.usability_score,
        storytelling_score: vote.storytelling_score,
        reason: vote.reason&.truncate(200),
        votes_url: "https://stardance.hackclub.com/votes/new"
      }
    )
  end
end
