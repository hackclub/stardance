require "test_helper"

class Admin::Missions::ShopUnlockGrantsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user(slack_id: "U_GRANTS_ADMIN", display_name: "grants-admin")
    @admin.grant_role!(:admin)
    @builder = create_user(slack_id: "U_GRANTS_BUILDER", display_name: "Ks_Builder")
    @mission = create_mission
  end

  test "an admin grants and revokes a user's shop unlocks, with an audit trail" do
    sign_in @admin

    post admin_mission_shop_unlock_grants_path(@mission.slug),
         params: { mission_shop_unlock_grant: { user_id: "@ks_builder", reason: "Shipped before attaching" } }

    grant = @mission.shop_unlock_grants.find_by!(user: @builder)
    assert_equal @admin, grant.granted_by
    assert_equal "Shipped before attaching", grant.reason
    assert_equal "Ks_Builder can now buy this mission's shop items.", flash[:shop_unlock_grants_notice]

    delete admin_mission_shop_unlock_grant_path(@mission.slug, grant)
    assert_not @mission.shop_unlock_grants.exists?

    versions = PaperTrail::Version.where(item_type: "Mission::ShopUnlockGrant", item_id: grant.id.to_s)
    assert_equal %w[create destroy], versions.order(:created_at).pluck(:event)
    assert_equal [ @admin.id.to_s ], versions.pluck(:whodunnit).uniq

    get admin_mission_path(@mission.slug)
    assert_response :success
    assert_includes response.body, "Mission::ShopUnlockGrant"
  end

  test "an unknown or already-granted user reports inside the frame" do
    sign_in @admin

    post admin_mission_shop_unlock_grants_path(@mission.slug),
         params: { mission_shop_unlock_grant: { user_id: "nobody-by-this-name" } }
    assert_match(/No user found/, flash[:shop_unlock_grants_alert])

    2.times do
      post admin_mission_shop_unlock_grants_path(@mission.slug),
           params: { mission_shop_unlock_grant: { user_id: @builder.id.to_s } }
    end
    assert_equal "Ks_Builder already has this mission's shop unlocks.", flash[:shop_unlock_grants_alert]
  end

  test "a non-admin mission owner can't grant shop unlocks" do
    owner = create_user(slack_id: "U_GRANTS_OWNER", display_name: "grants-owner")
    @mission.memberships.create!(user: owner, role: :owner)
    sign_in owner

    post admin_mission_shop_unlock_grants_path(@mission.slug),
         params: { mission_shop_unlock_grant: { user_id: @builder.id.to_s } }

    assert_not @mission.shop_unlock_grants.exists?
  end
end
