# frozen_string_literal: true

class SlackMessageCounterService
  CHANNEL_IDS = {
    stardance: "C09MPB8NE8H",
    stardance_support: "C09MATKQM8C" # stardance-help channel (support)
  }.freeze

  class << self
    # Fetch message counts for all users in a channel within a time period
    # Returns a hash of {slack_id => count}, or nil if the fetch failed
    # @param channel_key [Symbol] The channel key from CHANNEL_IDS
    # @param days_back [Integer] Number of days to look back (default: 14)
    # @param max_retries [Integer] Maximum number of retry attempts (default: 3)
    # @return [Hash, nil] Hash mapping slack_id to message count, or nil on API failure
    def fetch_all_message_counts(channel_key, days_back: 14, max_retries: 3)
      channel_id = CHANNEL_IDS[channel_key.to_sym]
      return {} unless channel_id

      oldest_timestamp = days_back.days.ago.to_i.to_s

      retry_with_backoff(max_retries) do
        fetch_channel_message_counts(channel_id, oldest_timestamp)
      end
    rescue Slack::Web::Api::Errors::SlackError => e
      Rails.logger.error("SlackMessageCounterService: Failed to fetch messages after retries: #{e.message}")
      nil
    rescue StandardError => e
      Rails.logger.error("SlackMessageCounterService: Unexpected error after retries: #{e.message}")
      nil
    end

    private

    # Retry a block with exponential backoff on rate limit errors
    # @param max_retries [Integer] Maximum number of retry attempts
    # @yield The block to execute with retry logic
    # @return The result of the block
    def retry_with_backoff(max_retries)
      attempt = 0

      loop do
        begin
          return yield
        rescue Slack::Web::Api::Errors::TooManyRequestsError => e
          attempt += 1

          if attempt > max_retries
            Rails.logger.error("SlackMessageCounterService: Max retries (#{max_retries}) exceeded for rate limiting")
            raise
          end

          # Extract retry_after from the error or use exponential backoff
          wait_time = extract_retry_after(e) || (2 ** attempt)

          Rails.logger.warn(
            "SlackMessageCounterService: Rate limited (attempt #{attempt}/#{max_retries}), " \
            "waiting #{wait_time} seconds before retry"
          )

          sleep(wait_time)
        rescue StandardError => e
          # Check if the error message indicates rate limiting
          if e.message =~ /retry after (\d+)/i
            attempt += 1

            if attempt > max_retries
              Rails.logger.error("SlackMessageCounterService: Max retries (#{max_retries}) exceeded")
              raise
            end

            wait_time = $1.to_i

            Rails.logger.warn(
              "SlackMessageCounterService: Rate limited (attempt #{attempt}/#{max_retries}), " \
              "waiting #{wait_time} seconds before retry"
            )

            sleep(wait_time)
          else
            # Not a rate limit error, re-raise immediately
            raise
          end
        end
      end
    end

    # Extract retry_after value from Slack API error response
    # @param error [Slack::Web::Api::Errors::TooManyRequestsError] The error object
    # @return [Integer, nil] The number of seconds to wait, or nil if not found
    def extract_retry_after(error)
      # Prefer the retry_after attribute if provided by the Slack client
      if error.respond_to?(:retry_after) && error.retry_after
        return error.retry_after.to_i
      end

      # Fall back to reading retry-after from the response headers (e.g., Faraday response)
      return nil unless error.respond_to?(:response) && error.response

      response = error.response
      headers = if response.respond_to?(:headers)
        response.headers
      else
        response
      end

      return nil unless headers.respond_to?(:[])

      retry_after_value = headers["retry-after"] || headers["Retry-After"]
      return nil unless retry_after_value

      # Ensure we only convert purely numeric values
      retry_after_str = retry_after_value.to_s.strip
      return nil unless retry_after_str.match?(/\A\d+\z/)

      retry_after_str.to_i
    end

    def fetch_channel_message_counts(channel_id, oldest_timestamp)
      client = Slack::Web::Client.new(token: Rails.application.credentials.dig(:slack, :bot_token))
      user_counts = Hash.new(0)
      cursor = nil
      page_number = 0

      Rails.logger.info("SlackMessageCounterService: Fetching message counts for channel #{channel_id}")

      loop do
        page_number += 1
        Rails.logger.info("SlackMessageCounterService: Fetching page #{page_number} for channel #{channel_id}")

        response = client.conversations_history(
          channel: channel_id,
          oldest: oldest_timestamp,
          limit: 999,
          cursor: cursor
        )

        break unless response.ok && response.messages.present?

        Rails.logger.info("SlackMessageCounterService: Page #{page_number} returned #{response.messages.size} messages")

        # Count top-level messages by user
        response.messages.each do |msg|
          if msg.user.present? && msg.subtype.nil?
            user_counts[msg.user] += 1
          end
        end

        # Count thread replies by user
        threaded_messages = response.messages.select { |msg| msg.reply_count.to_i > 0 }
        Rails.logger.info("SlackMessageCounterService: Page #{page_number} has #{threaded_messages.size} threaded messages to process")

        threaded_messages.each do |msg|
          thread_counts = count_thread_replies_by_user(client, channel_id, msg.ts)
          thread_counts.each do |slack_id, count|
            user_counts[slack_id] += count
          end

          # Rate limiting: sleep briefly between thread fetches
          sleep(0.1) if threaded_messages.size > 10
        end

        # Check if there are more pages
        cursor = response.response_metadata&.next_cursor
        has_more = cursor.present?
        Rails.logger.info("SlackMessageCounterService: Page #{page_number} complete. Has more pages: #{has_more}")
        break if cursor.blank?

        # Rate limiting: sleep 1 minute 10 seconds between pages
        Rails.logger.info("SlackMessageCounterService: Sleeping 70 seconds before fetching next page...")
        sleep(70)
      end

      Rails.logger.info("SlackMessageCounterService: Counted messages for #{user_counts.size} users")
      Rails.logger.info("SlackMessageCounterService: Final user counts hash: #{user_counts.inspect}")
      user_counts
    end

    def count_thread_replies_by_user(client, channel_id, thread_ts)
      user_counts = Hash.new(0)
      cursor = nil
      first_page = true
      thread_page_number = 0

      loop do
        thread_page_number += 1

        replies = client.conversations_replies(
          channel: channel_id,
          ts: thread_ts,
          oldest: thread_ts, # Start from thread parent
          limit: 999,
          cursor: cursor
        )

        break unless replies.ok && replies.messages.present?

        Rails.logger.info("SlackMessageCounterService: Thread #{thread_ts} page #{thread_page_number} returned #{replies.messages.size} replies")

        # Skip first message (parent) only on first page, count all replies by user
        messages_to_count = first_page ? replies.messages.drop(1) : replies.messages
        messages_to_count.each do |reply|
          if reply.user.present? && reply.subtype.nil?
            user_counts[reply.user] += 1
          end
        end

        first_page = false

        # Check if there are more pages
        cursor = replies.response_metadata&.next_cursor
        has_more = cursor.present?
        Rails.logger.info("SlackMessageCounterService: Thread #{thread_ts} page #{thread_page_number} complete. Has more pages: #{has_more}")
        break if cursor.blank?

        # Rate limiting: sleep between pages
        sleep(0.1)
      end

      user_counts
    end
  end
end
