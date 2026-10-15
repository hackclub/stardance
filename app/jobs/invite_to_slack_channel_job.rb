class InviteToSlackChannelJob < ApplicationJob
  queue_as :latency_5m

  def perform(user_id, channel_ids)
    user = User.find_by(id: user_id)
    return unless user&.slack_id.present?
    return if user.hardware_channel_invited_at.present?

    client = Slack::Web::Client.new(token: Rails.application.credentials.dig(:slack, :bot_token))
    Array(channel_ids).each do |channel_id|
      client.conversations_invite(channel: channel_id, users: user.slack_id)
    rescue Slack::Web::Api::Errors::SlackError => e
      raise unless e.message == "already_in_channel"
    end
    user.update_column(:hardware_channel_invited_at, Time.current)
  rescue Slack::Web::Api::Errors::SlackError => e
    Rails.logger.error("InviteToSlackChannelJob failed for user #{user_id}: #{e.message}")
  end
end
