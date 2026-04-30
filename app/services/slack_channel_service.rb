# frozen_string_literal: true

class SlackChannelService
  CHANNEL_IDS = {
    stardance_help: "C09MATKQM8C", # to-do: update with new channel ID
    stardance: "C0APH2MMHH7",
    stardance_introduction: "C0A4R38SFJ9" # to-do: update with new channel ID
  }.freeze

  CACHE_TTL = 5.minutes

  class << self
    def user_has_posted_in?(user, channel_key)
      return false unless user.slack_id.present?

      channel_id = CHANNEL_IDS[channel_key.to_sym]
      return false unless channel_id

      cache_key = "slack_channel_participation:#{user.id}:#{channel_key}"

      Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
        fetch_user_posted_in_channel?(user.slack_id, channel_id)
      end
    end

    private

    MAX_THREADS_TO_CHECK = 20

    def fetch_user_posted_in_channel?(slack_id, channel_id)
      client = Slack::Web::Client.new(token: Rails.application.credentials.dig(:slack, :bot_token))

      response = client.conversations_history(
        channel: channel_id,
        limit: 200
      )

      return false unless response.ok && response.messages.present?

      # Check top-level messages first (cheap)
      return true if response.messages.any? { |msg| msg.user == slack_id }

      # Check thread replies for messages that have threads
      threaded = response.messages.select { |msg| msg.reply_count.to_i > 0 }
      threaded.first(MAX_THREADS_TO_CHECK).each do |msg|
        replies = client.conversations_replies(
          channel: channel_id,
          ts: msg.ts,
          limit: 200
        )
        next unless replies.ok && replies.messages.present?

        # Skip first message (parent, already checked above)
        return true if replies.messages.drop(1).any? { |reply| reply.user == slack_id }
      end

      false
    rescue Slack::Web::Api::Errors::SlackError => e
      Rails.logger.error("SlackChannelService: Failed to fetch channel history: #{e.message}")
      false
    rescue StandardError => e
      Rails.logger.error("SlackChannelService: Unexpected error: #{e.message}")
      false
    end
  end
end
