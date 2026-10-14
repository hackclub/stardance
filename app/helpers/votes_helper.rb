module VotesHelper
  DISCARD_EVENT_TYPES = %w[vote_discarded vote_flag_accepted vote_auto_discarded].freeze

  # Says who threw a rating out and why. Reads the loaded events association so
  # the admin votes table stays a single query.
  def vote_discard_note(vote)
    event = vote.events.detect { |vote_event| DISCARD_EVENT_TYPES.include?(vote_event.event_type) }
    return if event.nil?

    reviewer = event.user&.display_name || "unknown"

    case event.event_type
    when "vote_auto_discarded" then "automated"
    when "vote_flag_accepted" then "flag accepted by #{reviewer}"
    else [ "by #{reviewer}", event.properties["reason"].presence ].compact.join(": ")
    end
  end

  def score_tone(score)
    case score
    when 1..3 then "low"
    when 4..6 then "mid"
    else "high"
    end
  end

  def vote_duration_in_words(seconds)
    return "—" if seconds.blank?

    minutes, secs = seconds.divmod(60)
    if minutes >= 60
      hours, minutes = minutes.divmod(60)
      "#{hours}h #{minutes}m"
    elsif minutes.positive?
      "#{minutes}m #{secs}s"
    else
      "#{secs}s"
    end
  end
end
