class SidebarComponent < ViewComponent::Base
  # ViewComponent doesn't auto-expose gem-provided view helpers, so the
  # template would otherwise have to call `helpers.inline_svg_tag`. Forward
  # it so the template stays readable. (ActionView's own helpers like
  # link_to, image_tag, form_with, etc. are already available.)
  delegate :inline_svg_tag, to: :helpers

  attr_reader :user

  def initialize(user: nil, active_slug_override: nil)
    @user = user
    @active_slug_override = active_slug_override.presence
  end

  def signed_in?
    user.present?
  end

  # Ordered list of nav items rendered in the sidebar. Each entry:
  #   slug:           data-onboarding-target value + identifier
  #   label:          visible text
  #   path:           href (or "#" for inert items)
  #   icon:           one of:
  #                     - String basename (e.g. "home") -> icons/home.svg, inline-SVG tinted via currentColor
  #                     - Hash { idle:, active: } -> two PNGs in icons/, swapped when nav link is active
  #                     - :avatar -> user's profile picture
  #   active_prefix:  optional path prefix that overrides default match (used to
  #                   highlight "my projects" on any /users/* route)
  def nav_items
    items = [
      { slug: "home",          label: "home",          path: helpers.home_path,
        icon: { idle: "rocket", active: "rocket_active" } }
    ]

    if signed_in? && Notification.enabled_for?(user)
      items << { slug: "notifications", label: "notifications", path: helpers.my_notifications_path,
        icon: { idle: "bell", active: "bell_active" }, badge: unread_notifications_count }
    end

    items << { slug: "rate",    label: "rate",          path: helpers.new_rate_path,
      icon: { idle: "box", active: "box_active" } }

    items.concat([
      { slug: "missions",      label: "missions",      path: helpers.missions_path,
        icon: { idle: "calendar", active: "calendar_active" } },
      { slug: "shop",          label: "shop",          path: "/shop",
        icon: { idle: "cart", active: "cart_active" },
        notify: signed_in? && user.shop_tutorial_notify? },
      { slug: "resources",     label: "resources",     path: helpers.guides_path,
        icon: { idle: "book", active: "book_active" } }
    ])

    if signed_in?
      items << {
        slug: "projects",
        label: "my projects",
        path: helpers.profile_projects_path(user.display_name),
        icon: :avatar,
        active_prefix: "/@"
      }

      items << {
        slug: "admin",
        label: "admin",
        path: helpers.admin_root_path,
        icon: "eye"
      } if user.roles.any?
    end

    items
  end

  # First-render active state (the sidebar_active Stimulus controller takes
  # over once the page is interactive and keeps the highlight in sync as the
  # user navigates Turbo-style).
  def active?(item)
    return item[:slug] == @active_slug_override if @active_slug_override

    candidate_path = item[:path]
    return false if candidate_path == "#"

    if item[:active_prefix].present?
      helpers.request.path.start_with?(item[:active_prefix])
    else
      helpers.current_page?(candidate_path) ||
        helpers.request.path == candidate_path ||
        helpers.request.path.start_with?("#{candidate_path}/")
    end
  end

  def link_classes_for(item)
    [ "sidebar__nav-link", ("sidebar__nav-link--active" if active?(item)) ].compact.join(" ")
  end

  def unread_notifications_count
    return 0 unless user
    return 0 unless Notification.table_exists?

    # First-render value only; ActionCable pushes live updates after the page
    # loads, so a brief staleness here is invisible to the user.
    @unread_notifications_count ||= Notification.unread_count_for(user)
  end
end
