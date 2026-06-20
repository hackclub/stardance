# frozen_string_literal: true

require "set"

namespace :slack_emotes do
  desc "Import custom emoji from the Slack workspace into the Stardance emoji picker"
  task import: :environment do
    token = Rails.application.credentials.dig(:slack, :bot_token) || ENV["SLACK_BOT_TOKEN"]

    if token.blank?
      puts "Skipped Slack emote import: missing slack.bot_token credential or SLACK_BOT_TOKEN"
      next
    end

    client = Slack::Web::Client.new(
      token:
    )

    response = client.emoji_list
    raw_emoji = response.emoji.to_h

    resolved = raw_emoji.each_with_object({}) do |(name, value), emotes|
      next if name.blank?

      emotes[name] = resolve_slack_emote_url(name, value, raw_emoji)
    end.compact

    emotes = resolved.sort.map do |name, url|
      {
        id: name,
        name: name.tr("_-", " ").titleize,
        keywords: name.split(/[_-]+/),
        skins: [ { src: url } ]
      }
    end

    SlackEmoteRegistry::PATH.dirname.mkpath
    SlackEmoteRegistry::PATH.write("#{JSON.pretty_generate(emotes)}\n")
    SlackEmoteRegistry.clear_cache!

    puts "Imported #{emotes.size} Slack emotes into #{SlackEmoteRegistry::PATH.relative_path_from(Rails.root)}"
  end

  def resolve_slack_emote_url(name, value, raw_emoji, seen = Set.new)
    return nil if value.blank?
    return value if value.start_with?("https://")
    return nil unless value.start_with?("alias:")

    alias_name = value.delete_prefix("alias:")
    return nil if alias_name == name || seen.include?(alias_name)

    resolve_slack_emote_url(alias_name, raw_emoji[alias_name], raw_emoji, seen.add(name))
  end
end
