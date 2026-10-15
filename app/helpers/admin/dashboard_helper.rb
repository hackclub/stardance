module Admin
  module DashboardHelper
    # `featured` gives a button the filled treatment, for the one destination
    # on the page that aggregates the others.
    def admin_page_button(label, path, enabled:, count: nil, featured: false)
      link_to path,
        class: class_names("btn-secondary admin-dashboard__button",
                           "admin-dashboard__button--featured" => featured,
                           "disabled" => !enabled) do
        if count
          safe_join([ label, turbo_frame_tag("admin_count_#{count}",
            src: admin_dashboard_count_path(count), loading: :lazy) ], " ")
        else
          label
        end
      end
    end

    def greeting_message(user)
      name = user.first_name.presence || user.display_name
      time_of_day =
        case Time.current.in_time_zone(user.timezone.presence || "UTC").hour
        when 0..4 then "burning the midnight oil, #{name}?"
        when 5..11 then "good morning, #{name}"
        when 12..16 then "good afternoon, #{name}"
        else "good evening, #{name}"
        end

      [
        time_of_day,
        "back at it, #{name}!",
        "welcome back, #{name}!",
        "what's on the docket, #{name}?",
        "howdy!",
        "you look wonderful today",
        "hiya :3",
        "ground control to #{name}",
        "another day among the stars",
        "you again? excellent :>"
      ].sample
    end
  end
end
