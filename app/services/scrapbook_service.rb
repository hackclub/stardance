class ScrapbookService
  SCRAPBOOK_CHANNEL_ID = "C01504DCLVD".freeze

  VALIDATION_ERRORS = {
    not_hackclub: "must be a Hack Club Slack URL",
    invalid_format: "is not a valid Slack message URL",
    wrong_channel: "must be from the #scrapbook channel",
    not_found: "could not be verified - message not found"
  }.freeze

  class << self
    def populate_devlog_from_url(devlog_id) = new(devlog_id).call

    def extract_ids(url)
      match = url.to_s.match(%r{/archives/([A-Z0-9]+)/p(\d+)})
      return [ nil, nil ] unless match

      [ match[1], "#{match[2][0..9]}.#{match[2][10..]}" ]
    end

    def validate_url(url)
      return :not_hackclub unless url.to_s.include?("hackclub") && url.to_s.include?("slack.com")

      channel_id, ts = extract_ids(url)
      return :invalid_format unless channel_id && ts
      return :wrong_channel unless channel_id == SCRAPBOOK_CHANNEL_ID
      return :not_found unless message_exists?(channel_id, ts)

      nil
    end

    def message_exists?(channel_id, ts)
      slack_client.conversations_replies(channel: channel_id, ts: ts, limit: 1).messages.present?
    rescue Slack::Web::Api::Errors::SlackError
      false
    end

    private

    def slack_client
      Slack::Web::Client.new(token: Rails.application.credentials.dig(:slack, :bot_token))
    end
  end

  def initialize(devlog_id)
    @devlog = Post::Devlog.find_by(id: devlog_id)
  end

  def call
    return unless devlog&.scrapbook_url.present?

    channel_id, ts = self.class.extract_ids(devlog.scrapbook_url)
    return unless channel_id == SCRAPBOOK_CHANNEL_ID && ts.present?

    message = fetch_message(channel_id, ts)
    return unless message

    attach_files(message)
    update_body(message)
    notify_thread(ts)

    devlog
  rescue StandardError => e
    log_error("ScrapbookService failed for devlog #{devlog&.id}", e)
    raise
  end

  private

  attr_reader :devlog

  def fetch_message(channel_id, ts)
    resp = slack.conversations_history(
      channel: channel_id,
      inclusive: true,
      oldest: ts,
      latest: ts,
      limit: 1
    )

    debug("Slack response #{channel_id}/#{ts}", resp.to_h)
    resp.ok && resp.messages&.first
  rescue Slack::Web::Api::Errors::SlackError => e
    log_error("Failed to fetch Slack message #{channel_id}/#{ts}", e)
    nil
  end

  def update_body(message)
    text = message["text"].to_s.strip
    return if text.blank?

    devlog.update!(body: text)
  end

  def attach_files(message)
    Array(message["files"]).each { |f| attach_file(f) }
  end

  def attach_file(file)
    url = file["url_private_download"]
    type = file["mimetype"]
    name = file["name"]

    return unless url.present?
    return unless Post::Devlog::ACCEPTED_CONTENT_TYPES.include?(type)

    resp = Faraday.get(url) { |req| req.headers["Authorization"] = "Bearer #{token}" }
    return unless resp.success?

    devlog.attachments.attach(
      io: StringIO.new(resp.body),
      filename: name,
      content_type: type
    )
  rescue StandardError => e
    log_error("Failed to attach Slack file #{file&.dig("name")}", e)
  end

  def notify_thread(ts)
    SendSlackDmJob.perform_later(
      SCRAPBOOK_CHANNEL_ID,
      "This scrapbook post has been linked to a Stardance devlog! :flavortown: " \
      "https://flavortown.hackclub.com/projects/#{devlog.id}",
      thread_ts: ts
    )
  end

  def slack
    @slack ||= Slack::Web::Client.new(token: token)
  end

  def token
    Rails.application.credentials.dig(:slack, :bot_token)
  end

  def debug(label, payload)
    Rails.logger.debug("#{label}: #{payload}") if Rails.env.development?
  end

  def log_error(prefix, err)
    Rails.logger.error("#{prefix}: #{err.class}: #{err.message}")
    Rails.logger.error(err.backtrace.join("\n")) if Rails.env.development?
  end
end
