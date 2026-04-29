# frozen_string_literal: true

module Admin
  module SuperMegaDashboard
    module NpsStats
      extend ActiveSupport::Concern

      private

      def load_nps_stats
        data = Rails.cache.fetch("super_mega_nps_stats", expires_in: 5.minutes) do
          with_dashboard_timing("nps") do
            build_nps_stats_from_airtable
          end
        rescue StandardError => e
          Rails.logger.warn("[SuperMegaDashboard] NPS section unavailable (#{e.class}): #{e.message}")

          {
            total_nps: nil,
            response_count: nil,
            promoters: 0,
            neutrals: 0,
            detractors: 0,
            error: e.message.presence || "NPS stats are temporarily unavailable"
          }
        end

        @nps_total = data&.dig(:total_nps)
        @nps_response_count = data&.dig(:response_count)
        @nps_promoters = data&.dig(:promoters) || 0
        @nps_neutrals = data&.dig(:neutrals) || 0
        @nps_detractors = data&.dig(:detractors) || 0
        @nps_error = data&.dig(:error)
      end

      def load_nps_vibes_stats
        payload = Rails.cache.read("super_mega_nps_vibes")
        payload = payload.deep_symbolize_keys if payload.respond_to?(:deep_symbolize_keys)

        @nps_vibes_things_to_improve = payload&.dig(:things_to_improve) || []
        @nps_vibes_things_did_well = payload&.dig(:things_did_well) || []
        @nps_vibes_meta = payload&.dig(:meta) || {}
        @nps_vibes_error = payload&.dig(:error)
      end

      def build_nps_stats_from_airtable
        api_key = ENV["UNIFIED_DB_INTEGRATION_AIRTABLE_KEY"]

        programs_table = Norairrecord.table(api_key, "app3A5kJwYqxMLOgh", "YSWS Programs")
        program_record = programs_table.all(filter: "{Name} = 'Stardance'").first
        nps_score = program_record&.fields&.dig("NPS Score")
        response_count = program_record&.fields&.dig("NPS–Response Count")

        records = Norairrecord.table(api_key, "app3A5kJwYqxMLOgh", "NPS").all(filter: "{YSWS} = 'Stardance'")
        counts = count_nps_categories(records)

        {
          total_nps: nps_score&.round,
          response_count: response_count,
          promoters: counts[:promoters],
          neutrals: counts[:neutrals],
          detractors: counts[:detractors]
        }
      end

      def build_nps_vibes_from_airtable(limit: 500)
        airtable_api_key = ENV["UNIFIED_DB_INTEGRATION_AIRTABLE_KEY"]
        openrouter_api_key = ENV["OPENROUTER_API_KEY"]

        records = Norairrecord.table(airtable_api_key, "app3A5kJwYqxMLOgh", "NPS").all(
          filter: "{YSWS} = 'Stardance'",
          max_records: limit
        )
        responses = extract_nps_free_text_responses(records)

        return { error: "No NPS responses found (or all were blank)" } if responses.empty?

        sampled = sample_nps_responses(responses)
        sampled_responses = sampled[:sampled_responses]
        avg_score = avg_sampled_score(sampled_responses)

        formatted_did_well = format_ranked_free_text(sampled_responses, :did_well)
        formatted_improve = format_ranked_free_text(sampled_responses, :improve)

        prompt = build_nps_vibes_prompt(formatted_did_well: formatted_did_well, formatted_improve: formatted_improve)
        llm_response = openrouter_chat_completion(
          api_key: openrouter_api_key,
          messages: [ { role: "user", content: prompt } ],
          temperature: 0.2,
          max_tokens: 1_200,
          open_timeout: 5,
          timeout: 30
        )

        unless llm_response.success?
          log_openrouter_failure("NPS vibes LLM Failure", llm_response)
          return { error: openrouter_user_facing_error("NPS vibes generation failed", llm_response) }
        end

        content = parse_openrouter_content(llm_response)
        parsed = parse_or_repair_vibes_json(content, openrouter_api_key: openrouter_api_key)

        {
          things_did_well: Array(parsed[:things_did_well]).first(15),
          things_to_improve: Array(parsed[:things_to_improve]).first(15),
          meta: {
            analyzed_count: sampled_responses.length,
            sampled_detractors: sampled[:sampled_detractors],
            sampled_promoters_passives: sampled[:sampled_promoters_passives],
            sampling_strategy: "50/50 detractors vs promoters+passives",
            generated_at: Time.current.iso8601,
            avg_score: avg_score
          }
        }
      rescue StandardError => e
        { error: e.message.presence || "NPS vibes are temporarily unavailable" }
      end

      def repair_json_with_llm(text, openrouter_api_key:)
        snippet = text.to_s.strip[0, 8_000]

        repair_prompt = <<~PROMPT
          You are a JSON repair tool.

          TASK:
          - Take the INPUT below, which is intended to be JSON, and output ONLY valid JSON.
          - Do not add commentary.
          - Do not wrap in markdown fences.
          - Preserve the same schema and data as much as possible.
          - If there are extra leading/trailing characters, ignore them.

          REQUIRED SCHEMA:
          {
            "things_did_well": [
              { "theme": "...", "summary": "...", "count": 0, "examples": ["...", "..."] }
            ],
            "things_to_improve": [
              { "theme": "...", "summary": "...", "count": 0, "examples": ["...", "..."] }
            ]
          }

          INPUT:
          #{snippet}
        PROMPT

        resp = openrouter_chat_completion(
          api_key: openrouter_api_key,
          messages: [ { role: "user", content: repair_prompt } ],
          temperature: 0,
          max_tokens: 1_200,
          open_timeout: 5,
          timeout: 20
        )

        unless resp.success?
          log_openrouter_failure("NPS vibes JSON repair failed", resp, truncate_body_to: 800)
          raise JSON::ParserError, "JSON repair failed"
        end

        cleaned = clean_json_fences(parse_openrouter_content(resp))
        extract_first_json_object(cleaned) || cleaned
      end

      def extract_first_json_object(text)
        return nil if text.blank?

        start_idx = text.index("{")
        end_idx = text.rindex("}")
        return nil if start_idx.nil? || end_idx.nil? || end_idx <= start_idx

        text[start_idx..end_idx]
      end

      def clean_json_fences(text)
        text.to_s.gsub(/^```json\s*|```\s*$/, "").strip
      end

      def parse_openrouter_content(response)
        body = JSON.parse(response.body)
        body.dig("choices", 0, "message", "content").to_s
      rescue JSON::ParserError
        ""
      end

      def parse_or_repair_vibes_json(content, openrouter_api_key:)
        cleaned = clean_json_fences(content)
        json_text = extract_first_json_object(cleaned) || cleaned

        parsed = begin
          JSON.parse(json_text)
        rescue JSON::ParserError => e
          Rails.logger.warn("[SuperMegaDashboard] NPS vibes JSON parse failed, attempting repair: #{e.message}")
          repaired = repair_json_with_llm(json_text, openrouter_api_key: openrouter_api_key)
          JSON.parse(repaired)
        end

        parsed.respond_to?(:deep_symbolize_keys) ? parsed.deep_symbolize_keys : parsed
      end

      def openrouter_chat_completion(api_key:, messages:, temperature:, max_tokens:, open_timeout:, timeout:)
        Faraday.post("https://openrouter.ai/api/v1/chat/completions") do |req|
          req.headers["Authorization"] = "Bearer #{api_key}"
          req.headers["Content-Type"] = "application/json"
          req.options.open_timeout = open_timeout
          req.options.timeout = timeout
          req.body = {
            model: ENV.fetch("OPENROUTER_LLM_MODEL", "x-ai/grok-4.1-fast"),
            messages: messages,
            temperature: temperature,
            max_tokens: max_tokens
          }.to_json
        end
      end

      def openrouter_error_message(response)
        body_json = JSON.parse(response.body)
        body_json.dig("error", "message") || body_json.dig("message")
      rescue JSON::ParserError
        nil
      end

      def openrouter_request_id(response)
        response.headers["x-request-id"] || response.headers["x-openrouter-request-id"]
      end

      def openrouter_user_facing_error(prefix, response)
        msg = "#{prefix} (LLM error: #{response.status})"
        error_message = openrouter_error_message(response)
        error_message.present? ? "#{msg} — #{error_message}" : msg
      end

      def log_openrouter_failure(prefix, response, truncate_body_to: 1_200)
        request_id = openrouter_request_id(response)
        truncated_body = response.body.to_s[0, truncate_body_to]
        Rails.logger.error(
          "[SuperMegaDashboard] #{prefix} status=#{response.status} request_id=#{request_id} body=#{truncated_body}"
        )
      end

      def count_nps_categories(records)
        promoters = 0
        neutrals = 0
        detractors = 0

        Array(records).each do |rec|
          category = rec&.fields&.fetch("NPS Category", nil)

          case category
          when "Promoter"
            promoters += 1
          when "Neutral"
            neutrals += 1
          when "Detractor"
            detractors += 1
          end
        end

        { promoters: promoters, neutrals: neutrals, detractors: detractors }
      end

      def extract_nps_free_text_responses(records)
        max_text_chars_per_response = 180

        score_field = "On a scale from 1-10, how likely are you to recommend this YSWS to a friend?"
        did_well_field = "What are we doing well?"
        improve_field = "How can we improve?"

        Array(records).filter_map do |rec|
          fields = rec&.fields || {}
          score = parse_optional_integer(fields[score_field])

          did_well = normalize_free_text(fields[did_well_field], max_chars: max_text_chars_per_response)
          improve = normalize_free_text(fields[improve_field], max_chars: max_text_chars_per_response)

          next if did_well.blank? && improve.blank?

          { score: score, did_well: did_well.presence, improve: improve.presence }
        end
      end

      def parse_optional_integer(value)
        str = value.to_s.strip
        str.match?(/\A\d+\z/) ? str.to_i : str
      end

      def normalize_free_text(value, max_chars:)
        value.to_s.strip.gsub(/\s+/, " ")[0, max_chars]
      end

      def sample_nps_responses(responses)
        target_total_responses = [ responses.length, 200 ].min

        detractors, promoters_and_passives = responses.partition do |r|
          score = r[:score]
          score.is_a?(Integer) && score >= 0 && score <= 6
        end

        detractor_target = (target_total_responses / 2.0).floor
        promoter_passive_target = target_total_responses - detractor_target

        sampled_detractors = detractors.shuffle.take(detractor_target)
        sampled_promoters_and_passives = promoters_and_passives.shuffle.take(promoter_passive_target)

        remaining = target_total_responses - (sampled_detractors.length + sampled_promoters_and_passives.length)
        if remaining.positive?
          filler_pool = if sampled_detractors.length < detractor_target
            (detractors - sampled_detractors)
          else
            (promoters_and_passives - sampled_promoters_and_passives)
          end

          filler = filler_pool.shuffle.take(remaining)
          if sampled_detractors.length < detractor_target
            sampled_detractors.concat(filler)
          else
            sampled_promoters_and_passives.concat(filler)
          end
        end

        {
          sampled_responses: (sampled_detractors + sampled_promoters_and_passives).shuffle,
          sampled_detractors: sampled_detractors.length,
          sampled_promoters_passives: sampled_promoters_and_passives.length
        }
      end

      def avg_sampled_score(sampled_responses)
        scores = sampled_responses.map { |r| r[:score] }.select { |s| s.is_a?(Integer) && s.positive? }
        scores.any? ? (scores.sum.to_f / scores.length).round(2) : nil
      end

      def format_ranked_free_text(sampled_responses, key)
        max_ranked_lines_per_section = 80
        max_chars_per_section = 9_000

        counts = sampled_responses.filter_map { |r| r[key] }.tally
        ranked = counts.sort_by { |(_, count)| -count }

        lines = []
        used_chars = 0

        ranked.each do |(text, count)|
          break if lines.length >= max_ranked_lines_per_section
          next if text.blank?

          line = "#{lines.length + 1}. x#{count}: #{text}"
          next if line.length > max_chars_per_section

          projected = used_chars + line.length + 1
          break if projected > max_chars_per_section

          lines << line
          used_chars = projected
        end

        lines.join("\n")
      end

      def build_nps_vibes_prompt(formatted_did_well:, formatted_improve:)
        <<~PROMPT
          You are analyzing NPS free-text responses for a program.

          CONTEXT:
          - These are deduplicated free-text responses.
          - Each line has a frequency count and the verbatim response.
          - You must use the counts to determine the most common themes.
          - The input below may be truncated to fit an input token limit.

          THINGS YOU DID WELL INPUT (use for the "Things you did well" list):
          #{formatted_did_well}

          THINGS TO IMPROVE INPUT (use for the "Things you should improve" list):
          #{formatted_improve}

          TASK:
          - Build two grouped lists of themes:
            1) "Things you did well" (use did_well)
            2) "Things you should improve" (use improve)
          - Group by meaning, not by exact wording.
          - Prefer 6-10 themes per list, sorted by frequency.
          - For each theme, provide 2-3 short verbatim examples from the input (keep each example under 120 characters).

          OUTPUT INSTRUCTIONS:
          Return ONLY valid JSON (no markdown, no code fences) matching exactly this schema:
          {
            "things_did_well": [
              { "theme": "Short title", "summary": "1 sentence", "count": 12, "examples": ["...", "..."] }
            ],
            "things_to_improve": [
              { "theme": "Short title", "summary": "1 sentence", "count": 12, "examples": ["...", "..."] }
            ]
          }
        PROMPT
      end
    end
  end
end
