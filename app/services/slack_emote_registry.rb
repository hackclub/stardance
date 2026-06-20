class SlackEmoteRegistry
  PATH = Rails.root.join("public/slack_emotes.json").freeze
  SHORTCODE_PATTERN = /:([a-z0-9_+-]+):/i

  def self.all
    @all ||= begin
      unless PATH.exist?
        {}
      else
        JSON.parse(PATH.read).each_with_object({}) do |emote, registry|
          id = emote["id"].to_s
          src = emote.dig("skins", 0, "src").to_s
          registry[id] = src if id.match?(/\A[a-z0-9_+-]+\z/i) && src.start_with?("https://")
        end.freeze
      end
    rescue JSON::ParserError
      {}
    end
  end

  def self.cache_key
    return "missing" unless PATH.exist?

    stat = PATH.stat
    "#{stat.mtime.to_i}-#{stat.size}"
  end

  def self.clear_cache!
    @all = nil
  end
end
