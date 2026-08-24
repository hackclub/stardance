require "test_helper"

class Admin::PayoutReviewsControllerTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    Flipper.enable(:ship_event_payouts)

    @admin = create_role_user("admin", :admin)
    @nda_helper = create_role_user("nda_helper", :nda_helper)
    @owner = create_role_user("owner")
    @project = Project.create!(title: "Payout review navigation")
    @ship_event = create_ship_event("First ship")
  end

  teardown do
    Flipper.disable(:ship_event_payouts)
  end

  test "admin can open the payout review index" do
    sign_in @admin

    get admin_payout_reviews_path

    assert_response :success
  end

  test "NDA helper can open a ship review but not the payout queue" do
    sign_in @nda_helper

    get admin_payout_review_path(@ship_event)

    assert_response :success
    assert_select "a[href=?]", admin_project_path(@project), text: "← Back to project"
    assert_select "a[href=?]", admin_payout_reviews_path, count: 0

    get admin_payout_reviews_path

    assert_response :forbidden
  end

  test "project page links NDA helpers to the latest ship review" do
    newest_ship_event = create_ship_event("Latest ship")
    sign_in @nda_helper

    get admin_project_path(@project)

    assert_response :success
    assert_select "a[href=?]", admin_payout_review_path(newest_ship_event), text: "Payout details"
  end

  test "ship review navigation stays within the project" do
    newest_ship_event = create_ship_event("Latest ship")
    sign_in @nda_helper

    get admin_payout_review_path(@ship_event)

    assert_response :success
    assert_select "nav[aria-label='Project ships']" do
      assert_select "a[href=?]", admin_payout_review_path(@ship_event), text: "Ship ##{@ship_event.id}"
      assert_select "a[href=?]", admin_payout_review_path(newest_ship_event), text: "Ship ##{newest_ship_event.id}"
      assert_select "a[aria-current='page']", text: "Ship ##{@ship_event.id}"
    end
  end

  test "ordinary users cannot open ship payout reviews" do
    sign_in @owner

    get admin_payout_review_path(@ship_event)

    assert_response :not_found
  end

  private

  def create_role_user(label, role = nil)
    user = create_user(slack_id: "U_PAYOUT_REVIEW_#{label.upcase}", display_name: "payout_review_#{label}")
    user.grant_role!(role) if role
    user
  end

  def create_ship_event(body)
    ship_event = Post::ShipEvent.create!(body:, uploading_attachments: true)
    created_at = body == "First ship" ? 1.day.ago : Time.current
    Post.create!(postable: ship_event, project: @project, user: @owner, created_at:, updated_at: created_at)
    ship_event
  end
end
