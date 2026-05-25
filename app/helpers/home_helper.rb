module HomeHelper
  def id_verification_ui_for(user)
    return { variant: :danger, badge: "Unknown" } unless user

    if user.verification_needs_submission?
      { variant: :danger, badge: "Needs submission" }
    elsif user.verification_pending?
      { variant: :warning, badge: "Under Review" }
    elsif user.verification_verified?
      { variant: :success, badge: "Verified" }
    elsif user.verification_ineligible?
      { variant: :danger, badge: "Ineligible" }
    else
      { variant: :danger, badge: "Unknown" }
    end
  end

  def home_tab_link(label, path, current_tab, divider: true)
    is_active = current_tab == label

    link = link_to(
      label,
      path,
      class: "home-tabs__link #{'home-tabs__link--active' if is_active}",
      aria: (is_active ? { current: "page" } : {}),
      data: { turbo: true }
    )

    return link unless divider

    divider_svg = content_tag(
      :svg,
      class: "home-tabs__divider-sparkle",
      viewBox: "206.75 4 28.5 38",
      xmlns: "http://www.w3.org/2000/svg",
      focusable: "false"
    ) do
      tag.path(
        d: "M219.878 4.56347C220.11 3.49747 221.63 3.49747 221.862 4.56347L224.565 16.998C224.635 17.3195 224.856 17.5872 225.159 17.7162L234.99 21.9063C235.813 22.257 235.813 23.4233 234.99 23.774L225.159 27.9642C224.856 28.0932 224.635 28.3609 224.565 28.6824L221.862 41.1169C221.63 42.1829 220.11 42.1829 219.878 41.1169L217.175 28.6824C217.105 28.3609 216.884 28.0932 216.581 27.9642L206.75 23.774C205.927 23.4233 205.927 22.257 206.75 21.9063L216.581 17.7162C216.884 17.5872 217.105 17.3195 217.175 16.998L219.878 4.56347Z",
        fill: "#EEE7BB"
      )
    end

    safe_join([link, divider_svg])
  end
end
