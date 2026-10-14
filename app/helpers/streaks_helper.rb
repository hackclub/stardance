module StreaksHelper
  # Tooltip for a streak calendar cell, week or month: the day's coding time
  # plus which Sticky Streak day it is, whichever of the two applies. Nil when
  # there is nothing to say.
  def streak_day_tooltip(day)
    parts = []
    parts << "#{day[:coded_seconds] / 60} minutes" if !day[:future] && day[:coded_seconds] > 0

    if day[:sticky_day]
      sticky = "Sticky Streak day #{day[:sticky_day]}"
      sticky += " (ready to claim)" if day[:sticky_claimable]
      parts << sticky
    end

    parts.join(" · ").presence
  end
end
