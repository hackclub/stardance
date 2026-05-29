class Command
  attr_reader :id, :title, :path, :keywords, :icon, :method

  def initialize(id:, title:, path:, keywords: [], icon: nil, method: :get, visible: ->(_u) { true })
    @id = id; @title = title; @path = path
    @keywords = keywords; @icon = icon; @method = method; @visible = visible
  end

  def post? = method == :post

  # TODO: add admin
  ALL = [
    new(id: :home,         title: "Home",            path: "/home",            keywords: %w[dashboard start]),
    new(id: :vote,         title: "Vote",             path: "/rate/new",        keywords: %w[review projects rate],       icon: "star_outline"),
    new(id: :shop,         title: "Shop",             path: "/shop",            keywords: %w[store buy prizes stardust],  icon: "cart_outline"),
    new(id: :resources,    title: "Resources",        path: "/guides",          keywords: %w[guides help docs tutorials], icon: "resources"),
    new(id: :projects,     title: "My Projects",      path: "/projects",        keywords: %w[builds code work]),
    new(id: :balance,      title: "My Balance",       path: "/my/balance",      keywords: %w[stardust points wallet]),
    new(id: :achievements, title: "Achievements",     path: "/my/achievements", keywords: %w[badges trophies unlocked]),
    new(id: :leaderboard,  title: "Leaderboard",      path: "/leaderboard",     keywords: %w[rankings top scores]),
    new(id: :streamer_mode_on,  title: "Enable Streamer Mode",  path: "/my/settings/streamer_mode?enable=true",  keywords: %w[blur privacy stream sensitive hide], method: :post),
    new(id: :streamer_mode_off, title: "Disable Streamer Mode", path: "/my/settings/streamer_mode?enable=false", keywords: %w[blur privacy stream sensitive hide], method: :post)
  ].freeze

  def visible_to?(user) = @visible.call(user)

  def self.for_user(user)
    ALL.select { |cmd| cmd.visible_to?(user) }
  end

  def self.search(query, user)
    commands = for_user(user)
    return commands if query.blank?
    normalized = query.downcase.strip
    commands.select do |cmd|
      cmd.title.downcase.include?(normalized) ||
        cmd.keywords.any? { |kw| kw.include?(normalized) }
    end
  end
end
