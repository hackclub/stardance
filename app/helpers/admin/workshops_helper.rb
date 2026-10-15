module Admin::WorkshopsHelper
  # Eastern time with the zone abbreviation, so DST is never ambiguous.
  def workshop_time(time)
    time.in_time_zone(Workshop::TIME_ZONE).strftime("%Y-%m-%d %H:%M %Z")
  end
end
