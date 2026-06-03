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
      # { slug: "notifications", label: "notifications", path: "#",
      #   icon: { idle: "bell", active: "bell_active" } }
    ]

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
      items << { slug: "projects", label: "my projects",   path: helpers.profile_projects_path(user.display_name),
        icon: :avatar, active_prefix: "/@" }
    end

    # items << { slug: "support", label: "support", path: helpers.admin_support_path, icon: "help" } if helpers.admin_policy(:support_dashboard).show?
    # items << { slug: "fraud",   label: "fraud",   path: helpers.admin_fraud_path, icon: "code" } if helpers.admin_policy(:fraud_dashboard).show? && !user.admin?
    # items << { slug: "admin",   label: "admin",   path: helpers.admin_users_path, icon: "code" } if user.admin?
    # items << { slug: "shop",    label: "shop",    path: helpers.admin_shop_path, icon: "shopping_cart_1_fill" } if helpers.admin_policy(ShopItem).index?
    # items << { slug: "fulfil",  label: "fulfil",  path: helpers.admin_shop_orders_path(view: "fulfillment"), icon: "shopping_cart_1_fill" } if user.fulfillment_person? && !user.admin?
    # items << { slug: "seller",  label: "seller",  path: helpers.seller_orders_path, icon: "shopping_cart_1_fill" } if user.seller?
    # items << { slug: "certify", label: "certify", path: "https://review.hackclub.com/", icon: "ship" } if user.project_certifier?

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
end
