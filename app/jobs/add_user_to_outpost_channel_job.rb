class AddUserToOutpostChannelJob < ApplicationJob
  queue_as :latency_5m

  # #outpost — https://hackclub.enterprise.slack.com/archives/C0B04RP43TQ
  OUTPOST_CHANNEL_ID = "C0B04RP43TQ".freeze

  def perform(user_id)
    # Don't touch Slack from development unless explicitly opted in for testing
    # (set OUTPOST_SLACK_IN_DEV=1) — otherwise this would invite real people.
    return if Rails.env.development? && ENV["OUTPOST_SLACK_IN_DEV"].blank?

    user = User.find_by(id: user_id)
    return if user.nil?

    client = Slack::Web::Client.new(token: Rails.application.credentials.dig(:slack, :outpost_bot_token))

    slack_id = user.slack_id.presence || resolve_slack_id(client, user)
    return if slack_id.blank?

    client.conversations_invite(channel: OUTPOST_CHANNEL_ID, users: slack_id)
  rescue Slack::Web::Api::Errors::SlackError => e
    # The user is already a member — nothing to do.
    return if e.message == "already_in_channel"

    Rails.logger.error("Failed to add user #{user_id} to #outpost: #{e.message}")
  end

  private

  # When we don't have a Slack ID stored, resolve it from the user's email and
  # backfill it so later operations don't need to hit Slack again.
  def resolve_slack_id(client, user)
    return if user.email.blank?

    slack_id = client.users_lookupByEmail(email: user.email).user.id
    user.update_column(:slack_id, slack_id) if slack_id.present?
    slack_id
  rescue Slack::Web::Api::Errors::SlackError => e
    # No Slack account for this email (users_not_found), missing scope, etc.
    Rails.logger.info("Could not resolve Slack ID for user #{user.id}: #{e.message}")
    nil
  end
end
