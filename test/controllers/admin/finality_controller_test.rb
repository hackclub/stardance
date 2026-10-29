require "test_helper"

class Admin::FinalityControllerTest < ActionDispatch::IntegrationTest
  setup do
    Flipper.enable(Finality::FEATURE_FLAG)

    @admin = create_user(slack_id: "U_FINALITY_ADMIN", display_name: "finality_admin")
    @admin.grant_role!(:admin)
    @owner = create_user(slack_id: "U_FINALITY_OWNER", display_name: "finality_owner")

    project = Project.create!(title: "Finality page project")
    Project::Membership.create!(project: project, user: @owner, role: :owner)
    @ship_event = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true, certification_status: "approved")
    shipped_at = Time.utc(2026, 10, 27, 16)
    Post.create!(project: project, user: @owner, postable: @ship_event, created_at: shipped_at, updated_at: shipped_at)
    @ship_event.update_columns(payout: 100)
  end

  teardown do
    Flipper.disable(Finality::FEATURE_FLAG)
  end

  test "admin sees every ship in the window" do
    sign_in @admin

    get admin_finality_path

    assert_response :success
    assert_select "td", text: "Finality page project"
    assert_select ".finality-draw", count: 1
    assert_select "form[action=?]", freeze_pool_admin_finality_path
    assert_select "button", text: "Sync to Airtable", count: 0
  end

  test "draw controls are real admin forms even outside development" do
    sign_in @admin
    get admin_finality_path

    assert_response :success
    assert_select ".finality-draw", count: 1
    assert_select ".finality-draw form[action=?]", roll_admin_finality_path
    assert_select ".finality-draw__eyebrow", text: /private results/
    assert_select ".finality-draw", text: /fictional|demo_shipper/, count: 0
  end

  test "admin can award missing bonuses, and the run is audited" do
    sign_in @admin

    assert_difference -> { @owner.ledger_entries.where(created_by: Finality::BONUS_CREATED_BY).count }, 1 do
      assert_difference -> { PaperTrail::Version.where(event: "finality_bonus_award").count }, 1 do
        post award_admin_finality_path
      end
    end

    assert_redirected_to admin_finality_path
    assert_equal 8, Finality.bonus_entry(@ship_event.reload).amount
  end

  test "non-admins cannot open the page" do
    sign_in @owner

    get admin_finality_path

    assert_response :not_found
  end

  test "non-admins cannot freeze, roll or reroll by posting directly" do
    sign_in @owner
    assert_no_difference [ "Finality::RaffleDraw.count", "Finality::RaffleSelection.count" ] do
      post freeze_pool_admin_finality_path
      assert_response :not_found
      post roll_admin_finality_path, params: { prize_key: "vip" }
      assert_response :not_found
      post reroll_admin_finality_path, params: { selection_id: 1, reason: "Try" }
      assert_response :not_found
    end
  end

  test "admin saves selections, sees contact details after reload and rerolls with audit history" do
    sign_in @admin
    others = 3.times.map do |i|
      person = create_user(slack_id: "U_REPLACEMENT_#{i}", display_name: "replacement_#{i}", hca_linked: false)
      ship = Post::ShipEvent.create!(body: "Another test ship", uploading_attachments: true, certification_status: "approved")
      Post.create!(project: @ship_event.project, user: person, postable: ship, created_at: @ship_event.post.created_at)
      person
    end
    travel_to Finality.window.end + 1.day do
      post freeze_pool_admin_finality_path
      assert_redirected_to admin_finality_path
      post roll_admin_finality_path, params: { prize_key: "vip" }
      assert_redirected_to admin_finality_path(prize: "vip")
      selected = Finality::RaffleDraw.current.selections.active.first
      get admin_finality_path(prize: "vip")
      assert_response :success
      assert_select ".finality-draw__contact a[href=?]", "mailto:#{selected.user.email}"

      reason = "Reviewed prior offenses <script>alert('x')</script>"
      post reroll_admin_finality_path, params: { selection_id: selected.id, reason: reason }
      assert_redirected_to admin_finality_path(prize: "vip")
      get admin_finality_path(prize: "vip")
      assert_response :success
      assert_select ".finality-draw__history", text: /Reviewed prior offenses/
      assert_select ".finality-draw__history script", count: 0
      assert_equal @admin.id.to_s, selected.reload.versions.last.whodunnit

      Flipper.enable(Finality::RAFFLE_FEATURE_FLAG)
      get finality_raffle_path
      assert_response :success
      assert_select ".finality-draw, .finality-draw__history", count: 0
      [ @owner, *others ].each { |person| assert_not_includes response.body, person.email }
      assert_not_includes response.body, "Reviewed prior offenses"
    end
  ensure
    Flipper.disable(Finality::RAFFLE_FEATURE_FLAG)
  end

  test "admin gets a useful message when drawing before pool preparation" do
    sign_in @admin
    post roll_admin_finality_path, params: { prize_key: "vip" }
    assert_redirected_to admin_finality_path(prize: "vip")
    assert_match(/Freeze the approved entry pool/, flash[:alert])
  end
end
