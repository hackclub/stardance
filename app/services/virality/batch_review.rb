module Virality
  class BatchReview
    OPERATIONS = %w[approve reject hold release save].freeze

    def initialize(project:, mentions:, reviewer:, operation:, reason: nil, internal_note: nil,
                   review_checklist: [], manual_override: false, evidence: {})
      @project = project
      @mentions = mentions
      @reviewer = reviewer
      @operation = operation
      @reason = reason.to_s.strip.presence
      @internal_note = internal_note.to_s.strip.presence
      @review_checklist = review_checklist
      @manual_override = manual_override
      @evidence = evidence.transform_keys(&:to_s)
    end

    def call
      raise ArgumentError, "Unknown review action" unless OPERATIONS.include?(@operation)
      raise ArgumentError, "Select at least one mention" if @mentions.empty?
      raise ArgumentError, "Every mention must belong to #{@project.title}" unless @mentions.all? { |mention| mention.project_id == @project.id }

      ActiveRecord::Base.transaction do
        @mentions.map { |mention| review(mention) }
      end
    end

    private

    def review(mention)
      raise ArgumentError, "it has already been decided" unless mention.status == :pending

      mention.triage!(triage_attributes(mention))
      return mention unless @operation.in?(%w[approve reject])

      ViralityDecision.schedule!(mention: mention, reviewer: @reviewer, attributes: decision_attributes(mention))
    rescue ArgumentError, ActiveRecord::RecordInvalid => error
      raise ArgumentError, "Mention ##{mention.id}: #{error.message}"
    end

    def triage_attributes(mention)
      evidence = evidence_for(mention)
      attributes = {
        review_checklist: @review_checklist,
        platform: evidence[:platform].presence || mention.platform,
        metric_name: evidence[:metric_name].presence || mention.metric_name,
        metric_value: Integer(evidence[:metric_value], exception: false) || mention.metric_value
      }
      attributes[:internal_notes] = [ mention.internal_notes.presence, @internal_note ].compact.join("\n") if @internal_note
      attributes[:on_hold_at] = Time.current if @operation == "hold"
      attributes[:on_hold_at] = nil if @operation == "release"
      attributes
    end

    def decision_attributes(mention)
      evidence = evidence_for(mention)
      {
        action: @operation,
        tier: (evidence[:tier] if @operation == "approve"),
        reason: @reason,
        evidence: {
          platform: evidence[:platform], metric_name: evidence[:metric_name], metric_value: evidence[:metric_value],
          manual_override: (@manual_override ? "1" : "0"),
          eligibility_confirmed: (mention.eligibility_confirmed? ? "1" : "0")
        }.compact.stringify_keys
      }
    end

    def evidence_for(mention)
      entry = @evidence[mention.id.to_s] || evidence_by_link[ProjectReview.link_key(mention.url)]
      (entry || {}).to_h.symbolize_keys
    end

    def evidence_by_link
      @evidence_by_link ||= @project.mentions.where(id: @evidence.keys).to_h do |mention|
        [ ProjectReview.link_key(mention.url), @evidence[mention.id.to_s] ]
      end
    end
  end
end
