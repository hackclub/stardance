# The site-wide ticker of recent ships, shown as social proof along the bottom
# of every app page. Only ships the public could already see in the feed make
# it in: verified, unbanned authors, live projects, and no rejected or
# misfiled ships. Shop purchases are mixed in as the market's "downs" (stardust
# spent), without naming the buyer. Cached briefly since it renders on every
# page view.
class ShipTicker
  SHIP_LIMIT = 20
  PURCHASE_LIMIT = SHIP_LIMIT / 2
  CACHE_KEY = "ship_ticker/v3"
  CACHE_TTL = 5.minutes

  Ship = Data.define(:project_id, :project_title, :author, :hours)
  Purchase = Data.define(:shop_item_id, :item_name, :stardust)

  attr_reader :entries

  def self.current
    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { new }
  end

  def initialize
    ships = public_ships
      .order("posts.created_at DESC")
      .limit(SHIP_LIMIT)
      .pluck("posts.project_id", "projects.title", "users.display_name", "post_ship_events.hours_at_ship")
      .map { |row| Ship.new(*row) }
    @entries = interleave(ships, recent_purchases)
  end

  def empty?
    entries.none?(Ship)
  end

  private

  def public_ships
    Post.authored_by_verified
      .of_ship_events(join: true)
      .joins(:project)
      .where(users: { banned: false })
      .where.not(post_ship_events: { certification_status: Post::ShipEvent::HIDDEN_STATUSES })
      .where("post_ship_events.hours_at_ship > 0")
  end

  # Paid, standalone orders for items anyone can see in the shop.
  def recent_purchases
    ShopOrder.worth_counting
      .joins(:shop_item)
      .merge(ShopItem.listed.published)
      .where(parent_order_id: nil)
      .where("shop_orders.frozen_item_price > 0")
      .order(created_at: :desc)
      .limit(PURCHASE_LIMIT)
      .pluck(:shop_item_id, "shop_items.name", Arel.sql("shop_orders.frozen_item_price * shop_orders.quantity + shop_orders.frozen_modifiers_price"))
      .map { |id, name, stardust| Purchase.new(id, name, stardust.round) }
  end

  # Two ships, then a purchase, so the ups always outnumber the downs.
  def interleave(ships, purchases)
    ships.each_slice(2).zip(purchases).flatten.compact
  end
end
