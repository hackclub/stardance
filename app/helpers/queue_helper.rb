module QueueHelper
  # Queue turnarounds run from minutes to weeks, so the unit follows the
  # magnitude: hours while the wait still reads as "today", days beyond that.
  # Takes the hour figures the snapshot produces; nil means "not enough data".
  def queue_duration_in_words(hours)
    return "—" if hours.blank?
    return "under an hour" if hours < 1
    return pluralize(hours.round, "hour") if hours < 48

    days = hours / 24.0
    "#{number_with_precision(days, precision: days < 10 ? 1 : 0, strip_insignificant_zeros: true)} days"
  end
end
