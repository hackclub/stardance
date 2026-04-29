require "faraday/retry"

module Admin
  class SupportVibesController < Admin::ApplicationController
    def index
      authorize :admin, :access_support_vibes?
      @vibes = SupportVibes.order(period_end: :desc).limit(20)
      @support_vibes_history = @vibes.map { |d| [ d.period_end, d.overall_sentiment ] }
    end

    def create
      authorize :admin, :access_support_vibes?

      last_vibe = SupportVibes.order(period_end: :desc).first
      start_time = last_vibe ? last_vibe.period_end : 24.hours.ago
      end_time = Time.current

      begin
        response = nephthys_conn.get("/api/tickets") do |req|
          req.params["after"] = start_time.iso8601
          req.params["before"] = end_time.iso8601
        end

        unless response.success?
          redirect_to admin_support_vibes_path, alert: "Failed to fetch data from Nephthys."
          return
        end

        tickets = JSON.parse(response.body)

        begin
          open_tickets_response = nephthys_conn.get("/api/tickets?status=open")
          open_tickets = JSON.parse(open_tickets_response.body)
        rescue Faraday::Error
          open_tickets = []
        end

        if tickets.empty?
          redirect_to admin_support_vibes_path, notice: "No new tickets found in the specified time frame."
          return
        end

        questions_with_ts = tickets.map.with_index(1) do |t, i|
          ts = t["message_ts"]
          "#{i}. #{t["description"]} (#{ts || 'none'})"
        end.join("\n")

        open_questions_with_ts = open_tickets.map.with_index(1) do |t, i|
          ts = t["message_ts"]
          "#{i}. #{t["description"]} (#{ts || 'none'})"
        end.join("\n")

        prompt = <<~PROMPT
          Analyze the following support questions and summarize the current vibes.

          INPUT DATA (each question includes a message_ts in brackets):
          #{questions_with_ts}

          OPEN QUESTIONS (each question includes a message_ts in brackets):
          #{open_questions_with_ts}

          OUTPUT INSTRUCTIONS:
          Return ONLY valid JSON (no markdown formatting, no code blocks) with this exact schema:
          {
            "concerns": [
              {
                "title": "Short catchy title",
                "description": "Detailed explanation (2-3 sentences) of what users are worried about including context.",
                "messages": [
                  { "message_ts": "1234567890.12345", "content": "Exact message content here" },
                  ...
                ],
                "count": 3
              },
              ... (Top 5 concerns)
            ],
            "prominent_questions": [
              "Exact question asked by user?",
              ... (5-7 most common/impactful VERBATIM questions found in the text)
            ],
            "unresolved_queries": {
              "Theme/Category: Short description of questions (2-3 sentences) [COMMON/UNCOMMON/RARE — assigned priority based on how frequent the concern is amongst open tickets]": ["Exact question 1", "Exact question 2"],
              ... (For all major themes of unresolved questions, group them and list 2 VERBATIM questions for each)
            },
            "overall_sentiment": 0.5, // Float from -1.0 (very negative) to 1.0 (very positive)
            "rating": "medium" // One of: "low", "medium", "high"
          }
        PROMPT

        llm_response = Faraday.post("https://openrouter.ai/api/v1/chat/completions") do |req|
          req.headers["Authorization"] = "Bearer #{ENV['OPENROUTER_API_KEY']}"
          req.headers["Content-Type"] = "application/json"
          req.body = {
            model: "x-ai/grok-4.1-fast",
            messages: [
              { role: "user", content: prompt }
            ]
          }.to_json
        end

        unless llm_response.success?
          Rails.logger.error "LLM Failure: #{llm_response.status} body: #{llm_response.body}"
          redirect_to admin_support_vibes_path, alert: "LLM response failed."
          return
        end

        llm_body = JSON.parse(llm_response.body)
        content = llm_body.dig("choices", 0, "message", "content")
        cleaned_content = content.gsub(/^```json\s*|```\s*$/, "")

        data = JSON.parse(cleaned_content)

        SupportVibes.create!(
          period_start: start_time,
          period_end: end_time,
          concerns: data["concerns"],
          overall_sentiment: data["overall_sentiment"],
          notable_quotes: data["prominent_questions"],
          unresolved_queries: data["unresolved_queries"],
          rating: data["rating"],
          concern_messages: data["concerns"].map { |c| c["messages"] }
        )

        redirect_to admin_support_vibes_path, notice: "Support vibes updated successfully."

      rescue JSON::ParserError
        redirect_to admin_support_vibes_path, alert: "Received invalid JSON from Nephthys."
      rescue StandardError => e
        redirect_to admin_support_vibes_path, alert: "An error occurred: #{e.message}"
      end
    end

    private

    def nephthys_conn
      @nephthys_conn ||= Faraday.new("https://stardance.nephthys.hackclub.com") do |f|
        f.request :retry, max: 2, interval: 0.2, interval_randomness: 0.1, backoff_factor: 2
        f.options.open_timeout = 3
        f.options.timeout = 7
        f.response :raise_error
        f.adapter Faraday.default_adapter
      end
    end
  end
end
