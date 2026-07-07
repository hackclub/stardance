module VotesHelper
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
