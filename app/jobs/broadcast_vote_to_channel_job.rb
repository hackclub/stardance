class BroadcastVoteToChannelJob < ApplicationJob
  queue_as :default

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
        time_taken_to_vote: vote.time_taken_to_vote,
        demo_url_clicked: vote.demo_url_clicked,
        repo_url_clicked: vote.repo_url_clicked,
        reason: vote.reason&.truncate(200),
        suspicious: vote.suspicious?,
        dashboard_url: "https://stardance.hackclub.com/admin/vote_spam_dashboard/users/#{user.id}?window_days=365"
      }
    )
  end
end
