class Command
  attr_reader :id, :title, :path, :keywords, :icon, :method, :page, :focus

  def initialize(id:, title:, path: nil, keywords: [], icon: nil, method: :get, visible: ->(_u) { true }, page: nil, focus: nil)
    @id = id; @title = title; @path = path
    @keywords = keywords; @icon = icon; @method = method; @visible = visible
    @page = page; @focus = focus
  end

  def post? = method == :post

  HELPER = [
    { id: :users,       title: "Users",       path: "/users",       keywords: %w[users people],         icon: "people"       },
    { id: :projects,    title: "Projects",    path: "/projects",    keywords: %w[projects builds],      icon: "code"         },
    { id: :shop_orders, title: "Shop Orders", path: "/shop/orders", keywords: %w[orders shop],          icon: "cart_outline" },
    { id: :support,     title: "Support",     path: "/support",     keywords: %w[support tickets],      icon: "help"         }
  ].map { |a| new(**a.merge(
    id: :"helper_#{a[:id]}",
    title: "[HELPER] #{a[:title]}",
    path: "/admin#{a[:path]}",
    keywords: (a[:keywords] || []) | %w[helper],
    visible: ->(u) { u.helper? && !u.admin? }
  )) }.freeze

  ADMIN = [
    { id: :dashboard,            title: "Dashboard",          path: "/",                        keywords: %w[dashboard],                    icon: "admin_panel_settings" },
    { id: :users,                title: "Users",              path: "/users",                   keywords: %w[users people],                 icon: "people"               },
    { id: :user_perms,           title: "User Permissions",   path: "/user-perms",              keywords: %w[permissions roles grants],     icon: "people"               },
    { id: :projects,             title: "Projects",           path: "/projects",                keywords: %w[projects builds],              icon: "code"                 },
    { id: :support,              title: "Support",            path: "/support",                 keywords: %w[support tickets],              icon: "help"                 },
    { id: :fraud,                title: "Fraud",              path: "/fraud",                   keywords: %w[fraud suspicious],             icon: "warning"              },
    { id: :shop,                 title: "Shop",               path: "/shop",                    keywords: %w[shop store items],             icon: "cart_outline"         },
    { id: :shop_orders,          title: "Shop Orders",        path: "/shop/orders",             keywords: %w[orders shop],                  icon: "cart_outline"         },
    { id: :shop_suggestions,     title: "Shop Suggestions",   path: "/shop/suggestions",        keywords: %w[suggestions shop requests],    icon: "cart_outline"         },
    { id: :messages,             title: "Messages",           path: "/messages",                keywords: %w[messages],                     icon: "bell"                 },
    { id: :audit_logs,           title: "Audit Logs",         path: "/audit_logs",              keywords: %w[audit logs],                   icon: "resources"            },
    { id: :reports,              title: "Reports",            path: "/reports",                 keywords: %w[reports],                      icon: "resources"            },
    { id: :fulfillment_payouts,  title: "Fulfillment Payouts", path: "/fulfillment_payouts",     keywords: %w[fulfillment payouts],          icon: "cart_outline"         },
    { id: :missions,             title: "Missions",           path: "/missions",                keywords: %w[missions],                     icon: "star_outline"         },
    { id: :cert_ships,           title: "Certification Ships", path: "/certification/ship",      keywords: %w[certification ships review],   icon: "code"                 },
    { id: :cert_ysws,            title: "YSWS Reviews",       path: "/certification/review",    keywords: %w[ysws review certification],    icon: "code"                 }
  ].map { |a| new(**a.merge(
    id: :"admin_#{a[:id]}",
    title: "[ADMIN] #{a[:title]}",
    path: "/admin#{a[:path]}",
    keywords: (a[:keywords] || []) | %w[admin],
    visible: ->(u) { u.admin? }
  )) }.freeze
  ALL = [
    new(id: :create_post, title: "Create Post", keywords: %w[devlog post write compose blog], icon: "pencil", focus: '[data-composer-target="textarea"]', page: "/home"),
    new(id: :home,         title: "Home",            path: "/home",            keywords: %w[dashboard start]),
    new(id: :vote,         title: "Vote",             path: "/rate/new",        keywords: %w[review projects rate],       icon: "star_outline"),
    new(id: :shop,         title: "Shop",             path: "/shop",            keywords: %w[store buy prizes stardust],  icon: "cart_outline"),
    new(id: :resources,    title: "Resources",        path: "/resources",       keywords: %w[guides resources help docs tutorials], icon: "resources"),
    new(id: :projects,     title: "My Projects",      path: "/projects",        keywords: %w[builds code work]),
    new(id: :balance,      title: "My Balance",       path: "/my/balance",      keywords: %w[stardust points wallet]),
    new(id: :achievements, title: "Achievements",     path: "/my/achievements", keywords: %w[badges trophies unlocked]),
    new(id: :leaderboard,  title: "Leaderboard",      path: "/leaderboard",     keywords: %w[rankings top scores]),
    new(id: :streamer_mode_on,  title: "Enable Streamer Mode",  path: "/my/settings/streamer_mode?enable=true",  keywords: %w[blur privacy stream sensitive hide], method: :post),
    new(id: :streamer_mode_off, title: "Disable Streamer Mode", path: "/my/settings/streamer_mode?enable=false", keywords: %w[blur privacy stream sensitive hide], method: :post),
    *ADMIN,
    *HELPER
  ].freeze

  def visible_to?(user) = @visible.call(user)

  def self.for_user(user, current_path: nil)
    ALL.select { |cmd| cmd.visible_to?(user) && (cmd.page.nil? || cmd.page == current_path) }
  end

  def self.search(query, user, current_path: nil)
    commands = for_user(user, current_path: current_path)
    return commands if query.blank?
    normalized = query.downcase.strip
    commands.select do |cmd|
      cmd.title.downcase.include?(normalized) ||
        cmd.keywords.any? { |kw| kw.include?(normalized) }
    end
  end
end
