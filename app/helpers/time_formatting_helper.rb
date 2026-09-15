# Looking for an easy way to format time? you should probably just use the built-in rails ones!
# checkout distance_of_time_in_words or time_ago_in_words
#
# I found this codebase had something like 10 different implementations of
# doing something shorter, so this is just a DRY implementation everyone can
# use - @msw
#
# input takes in seconds, just like all time/durations stored in rails
#
# duration_in_words(1.hour)             => "1h"
# duration_in_words(1.hour + 1.minute)  => "1h 1m"
# duration_in_words(3700)               => "1h 1m"
# duration_in_words(45)                 => "45s"
# duration_in_words(90061)              => "1d 1h"
#
# duration_in_words(90.minutes, :short) => "1.5h"
# duration_in_words(2.5.hours, :short)  => "2.5h"
# duration_in_words(50.3.hours, :short) => "2.1d"

module TimeFormattingHelper
  def duration_in_words(value, style = :long)
    return "—" if value.nil?

    total = value.to_i
    return "0s" if total <= 0

    style == :short ? duration_short(total) : duration_long(total)
  end

  private

  def duration_short(total)
    case
    when total < 1.hour then "#{total / 1.minute}m"
    when total < 2.days then "#{tidy(total / 1.hour.to_f)}h"
    else                     "#{tidy(total / 1.day.to_f)}d"
    end
  end

  def duration_long(total)
    days,    total = total.divmod(1.day)
    hours,   total = total.divmod(1.hour)
    minutes, secs  = total.divmod(1.minute)

    parts = []
    parts << "#{days}d"    if days > 0
    parts << "#{hours}h"   if hours > 0
    parts << "#{minutes}m" if minutes > 0
    parts << "#{secs}s"    if secs > 0 && days == 0 && hours == 0

    parts.first(2).join(" ")
  end

  def tidy(n)
    n = n.round(1)
    n == n.floor ? n.to_i : n
  end
end
