module Admin
  module MegaDashboard
    # NPS for the program, read from the unified YSWS Airtable base.
    #
    # Ported from the old Super Mega dashboard with two changes: the program
    # row is fetched by record ID rather than by a `{Name} = '...'` filter, so
    # a rename can't silently zero the panel; and the promoter/detractor split
    # now comes off the program row directly, which that table carries today,
    # instead of paging the whole NPS table to tally it.
    class NpsStats
      BASE_ID = "app3A5kJwYqxMLOgh".freeze
      PROGRAMS_TABLE = "YSWS Programs".freeze
      PROGRAM_RECORD_ID = "recGrpHBL5sKls5nz".freeze
      NPS_TABLE = "NPS".freeze
      PROGRAM_NAME = "Stardance".freeze

      SCORE_FIELD = "On a scale from 1-10, how likely are you to recommend this YSWS to a friend?".freeze
      DID_WELL_FIELD = "What are we doing well?".freeze
      IMPROVE_FIELD = "How can we improve?".freeze

      # Free text is sampled 50/50 between detractors and everyone else, so the
      # themes aren't drowned out by the (usually far larger) happy majority.
      SAMPLE_SIZE = 200
      MAX_TEXT_CHARS = 180

      def self.configured? = api_key.present?

      def self.api_key
        ENV["UNIFIED_DB_INTEGRATION_AIRTABLE_KEY"].presence || ENV["AIRTABLE_API_KEY"].presence
      end

      def headline
        return { error: "No Airtable key configured" } unless self.class.configured?

        fields = program_record&.fields || {}
        {
          score: fields["NPS Score"]&.round,
          response_count: fields["NPS–Response Count"],
          promoters: fields["NPS–Promoter"].to_i,
          detractors: fields["NPS–Detractor"].to_i,
          needs_more_feedback: fields["NPS–Needs More Feedback"],
          median_estimated_hours: fields["NPS–Median Estimated Hours"]
        }
      rescue StandardError => e
        { error: e.message.presence || "NPS is temporarily unavailable" }
      end

      # Expensive (Airtable paging plus an LLM call), so this is only ever run
      # from the explicit refresh action, never on page load.
      def build_vibes
        return { error: "No Airtable key configured" } unless self.class.configured?

        responses = free_text_responses
        return { error: "No NPS free text found" } if responses.empty?

        sampled = sample(responses)
        parsed = Llm.themes(
          did_well: ranked(sampled, :did_well),
          improve: ranked(sampled, :improve)
        )
        return parsed if parsed[:error]

        {
          things_did_well: Array(parsed[:things_did_well]).first(15),
          things_to_improve: Array(parsed[:things_to_improve]).first(15),
          meta: {
            analyzed_count: sampled.size,
            average_score: average_score(sampled),
            generated_at: Time.current.iso8601
          }
        }
      rescue StandardError => e
        { error: e.message.presence || "NPS vibes are temporarily unavailable" }
      end

      private

      def program_record
        @program_record ||= Norairrecord.table(self.class.api_key, BASE_ID, PROGRAMS_TABLE).find(PROGRAM_RECORD_ID)
      end

      def free_text_responses
        records = Norairrecord.table(self.class.api_key, BASE_ID, NPS_TABLE)
                              .all(filter: "{YSWS} = '#{PROGRAM_NAME}'", max_records: 500)

        Array(records).filter_map do |record|
          fields = record&.fields || {}
          did_well = normalise(fields[DID_WELL_FIELD])
          improve = normalise(fields[IMPROVE_FIELD])
          next if did_well.blank? && improve.blank?

          { score: Integer(fields[SCORE_FIELD].to_s, exception: false), did_well: did_well.presence, improve: improve.presence }
        end
      end

      def normalise(value) = value.to_s.strip.gsub(/\s+/, " ")[0, MAX_TEXT_CHARS]

      def sample(responses)
        target = [ responses.size, SAMPLE_SIZE ].min
        detractors, others = responses.partition { |r| r[:score].is_a?(Integer) && r[:score] <= 6 }
        half = target / 2

        picked = detractors.sample(half) + others.sample(target - half)
        # If one side is short, top up from the other so the sample still
        # reaches the target rather than silently shrinking.
        shortfall = target - picked.size
        picked += (responses - picked).sample(shortfall) if shortfall.positive?
        picked.shuffle
      end

      # Deduplicated and frequency-ranked, so the model sees how often a theme
      # recurs instead of guessing from repetition in the raw list.
      def ranked(responses, key)
        responses.filter_map { |r| r[key] }
                 .tally
                 .sort_by { |_, count| -count }
                 .first(80)
                 .each_with_index
                 .map { |(text, count), index| "#{index + 1}. x#{count}: #{text}" }
                 .join("\n")
      end

      def average_score(responses)
        scores = responses.filter_map { |r| r[:score] }
        scores.any? ? (scores.sum.to_f / scores.size).round(2) : nil
      end
    end
  end
end
