require "test_helper"

class Admin::Missions::PrizesControllerTest < ActionDispatch::IntegrationTest
  PIXEL_PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")

  setup do
    @admin = create_user(slack_id: "U_PRZ_ADMIN", display_name: "prz-admin")
    @admin.grant_role!(:admin)
    @mission = create_mission
    @item = prize_item
    sign_in @admin
  end

  test "creating a prize persists the chosen category" do
    assert_difference -> { @mission.prizes.count }, 1 do
      post admin_mission_prizes_path(@mission.slug),
           params: { mission_prize: { shop_item_id: @item.id, category: "after_design" } }
    end
    assert_equal "after_design", @mission.prizes.order(:id).last.category
  end

  test "creating a prize without a category defaults to after_shipping" do
    post admin_mission_prizes_path(@mission.slug),
         params: { mission_prize: { shop_item_id: @item.id } }
    assert_equal "after_shipping", @mission.prizes.order(:id).last.category
  end

  test "updating a prize changes its category" do
    prize = @mission.prizes.create!(shop_item: @item, position: 0, category: :after_shipping)
    patch admin_mission_prize_path(@mission.slug, prize),
          params: { mission_prize: { category: "after_design" } }
    assert_equal "after_design", prize.reload.category
  end

  private

  def prize_item
    item = ShopItem.new(name: "Kit #{SecureRandom.hex(3)}", description: "d", ticket_cost: 0,
                        type: "ShopItem::ThirdPartyPhysical", enabled: true, mission_prize_only: true)
    item.image.attach(io: StringIO.new(PIXEL_PNG), filename: "i.png", content_type: "image/png")
    item.save!
    item
  end
end
