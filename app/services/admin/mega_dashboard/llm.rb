module Admin
  module MegaDashboard
    # Claude calls for the dashboard's qualitative panels.
    #
    # Theme clustering is a bounded classification job over a few hundred short
    # strings, so it runs on Haiku by default. Set ANTHROPIC_MODEL to
    # claude-sonnet-5 if the themes come back too shallow.
    module Llm
      DEFAULT_MODEL = "claude-haiku-4-5".freeze
      MAX_TOKENS = 4_000

      # Constrains the reply to this shape, which removes the parse-and-repair
      # dance the previous provider needed.
      THEMES_SCHEMA = {
        type: "object",
        properties: {
          things_did_well: { "$ref": "#/$defs/themes" },
          things_to_improve: { "$ref": "#/$defs/themes" }
        },
        required: %w[things_did_well things_to_improve],
        additionalProperties: false,
        "$defs": {
          themes: {
            type: "array",
            items: {
              type: "object",
              properties: {
                theme: { type: "string" },
                summary: { type: "string" },
                count: { type: "integer" },
                examples: { type: "array", items: { type: "string" } }
              },
              required: %w[theme summary count examples],
              additionalProperties: false
            }
          }
        }
      }.freeze

      module_function

      def configured? = ENV["ANTHROPIC_API_KEY"].present?

      def model = ENV.fetch("ANTHROPIC_MODEL", DEFAULT_MODEL)

      def themes(did_well:, improve:)
        return { error: "ANTHROPIC_API_KEY not configured" } unless configured?

        message = client.messages.create(
          model: model,
          max_tokens: MAX_TOKENS,
          system: "You group free-text survey responses into themes. Return only the requested JSON.",
          output_config: { format: { type: "json_schema", schema: THEMES_SCHEMA } },
          messages: [ { role: "user", content: themes_prompt(did_well: did_well, improve: improve) } ]
        )

        parse(message)
      rescue Anthropic::Errors::APIStatusError => e
        Rails.logger.error("[MegaDashboard] Claude #{e.class}: #{e.message}")
        { error: "Claude error (#{e.class.name.demodulize})" }
      rescue Anthropic::Errors::APIConnectionError
        { error: "Could not reach Claude" }
      end

      def client = @client ||= ::Anthropic::Client.new

      # A refusal or a truncated reply both leave the JSON unusable, so both are
      # reported rather than parsed.
      def parse(message)
        return { error: "Claude declined the request" } if message.stop_reason == "refusal"
        return { error: "Response hit the token limit" } if message.stop_reason == "max_tokens"

        text = message.content.filter_map { |block| block.text if block.type == :text }.join
        JSON.parse(text).deep_symbolize_keys
      rescue JSON::ParserError
        { error: "Claude returned unparseable JSON" }
      end

      def themes_prompt(did_well:, improve:)
        <<~PROMPT
          Group these NPS free-text responses into themes.

          Each line is "N. xCOUNT: text", where COUNT is how many people said
          something equivalent. Use the counts to judge how common a theme is.
          The lists may be truncated.

          THINGS WE DID WELL:
          #{did_well}

          THINGS TO IMPROVE:
          #{improve}

          Group by meaning rather than exact wording, and prefer 6-10 themes per
          list, most common first. Give each theme 2-3 short verbatim examples
          from the input, each under 120 characters. `count` is the number of
          responses behind the theme.
        PROMPT
      end
    end
  end
end
