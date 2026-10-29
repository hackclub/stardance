require "test_helper"

class Mission::ShopUnlockGrantTest < ActiveSupport::TestCase
  PIXEL_PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")

  setup do
    @admin = create_user(slack_id: "U_GRANT_ADMIN", display_name: "grant-admin")
    @builder = create_user(slack_id: "U_GRANT_BUILDER", display_name: "grant-builder")
    @mission = create_mission
    @item = ShopItem.new(name: "Mission Shirt", description: "test item", ticket_cost: 10,
                         type: "ShopItem::ThirdPartyPhysical", enabled: true)
    @item.image.attach(io: StringIO.new(PIXEL_PNG), filename: "px.png", content_type: "image/png")
    @item.save!
    Mission::ShopUnlock.create!(mission: @mission, shop_item: @item)
  end

  test "a grant unlocks the mission's shop items without completing the mission" do
    assert @item.mission_locked_for?(@builder)

    @mission.shop_unlock_grants.create!(user: @builder, granted_by: @admin)
    builder = User.find(@builder.id)

    assert_not @item.mission_locked_for?(builder)
    assert_not_includes builder.completed_mission_ids, @mission.id
    assert @item.mission_locked_for?(User.find(@admin.id)), "a grant is for one user only"
  end

  test "a user can only be granted a mission once" do
    @mission.shop_unlock_grants.create!(user: @builder, granted_by: @admin)
    duplicate = @mission.shop_unlock_grants.new(user: @builder, granted_by: @admin)

    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:user_id, :taken)
  end
end
