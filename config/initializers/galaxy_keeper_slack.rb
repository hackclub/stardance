# This is for the Galaxy Keeper bot's Slack initialization :D

class GalaxySlack
  def self.client
    @client ||= Slack::Web::Client.new(
      token: Rails.application.credentials.dig(:galaxy_bot_token) || ENV["SLACK_GALAXY_BOT_TOKEN"]
    )
  end
end