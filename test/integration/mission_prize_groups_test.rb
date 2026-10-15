require "test_helper"

class MissionPrizeGroupsTest < ActionDispatch::IntegrationTest
  PIXEL_PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")

  setup do
    @user = User.create!(email: "u-#{SecureRandom.hex(6)}@example.com",
                         display_name: "U#{SecureRandom.hex(3)}", slack_id: "U#{SecureRandom.hex(8)}")
    @mission = create_mission
  end

  test "single-category prizes render without group headers" do
    add_prize(:after_shipping, "Sticker")
    add_prize(:after_shipping, "Patch")

    sign_in @user
    get mission_path(@mission.slug)
    assert_response :success
    assert_select ".mission-home__prize-group-label", count: 0
  end

  test "a mission with an after-design kit splits into design and building sections" do
    add_prize(:after_design, "Kit")
    add_prize(:after_shipping, "Sticker")

    sign_in @user
    get mission_path(@mission.slug)
    assert_response :success
    assert_select ".mission-home__prize-group-label", count: 2
    assert_select ".mission-home__prize-group-label", text: "After design"
    assert_select ".mission-home__prize-group-label", text: "After building"
  end

  test "an after-design kit alone still splits into design and building sections" do
    add_prize(:after_design, "Kit")

    sign_in @user
    get mission_path(@mission.slug)
    assert_response :success
    assert_select ".mission-home__prize-group-label", text: "After design"
    assert_select ".mission-home__prize-group-label", text: "After building"
  end

  test "a hardware mission shows the per-hour stardust payout instead of community rating" do
    @mission.update!(hardware: true)
    add_prize(:after_design, "Kit")

    sign_in @user
    get mission_path(@mission.slug)
    assert_response :success
    assert_select ".mission-home__prize-title", text: "Gets stardust"
    assert_select ".mission-home__prize-blurb", text: /per hour/
    assert_select ".mission-home__prize-title", text: "Goes into rating", count: 0
  end

  private

  def add_prize(category, name)
    item = ShopItem.new(name: "#{name} #{SecureRandom.hex(3)}", description: "d", ticket_cost: 0,
                        type: "ShopItem::ThirdPartyPhysical", enabled: true, mission_prize_only: true)
    item.image.attach(io: StringIO.new(PIXEL_PNG), filename: "i.png", content_type: "image/png")
    item.save!
    @mission.prizes.create!(shop_item: item, position: @mission.prizes.count, category: category)
  end
end
