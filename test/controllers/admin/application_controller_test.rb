require "test_helper"

class Admin::ApplicationControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user("admin", :admin)
    @helper = create_user("helper", :helper)
    @fraud_reviewer = create_user("fraud", :fraud_dept)
  end

  test "admin sees mission control at /admin" do
    sign_in @admin

    get admin_root_path

    assert_response :success
    assert_select "h1", text: /Admin/
    assert_select "a[href=?]", admin_users_path
    assert_select "a[href=?]", admin_shop_path
    assert_select "a[href=?]", admin_mission_reviews_path
    assert_select ".admin-hub__wg", count: 0
  end

  test "show_wgs flag shows weighted grant count for actor" do
    approved_hours = Post.of_ship_events(join: true)
      .where(post_ship_events: { certification_status: "approved" })
      .where(project_id: Project.select(:id))
      .sum("post_ship_events.hours_at_ship")
    expected_count = (approved_hours.to_f / 10.0).round(2)
    formatted_count = ActionController::Base.helpers.number_with_precision(
      expected_count,
      precision: 2,
      strip_insignificant_zeros: true
    )

    Flipper.enable_actor(:show_wgs, @admin)
    sign_in @admin

    get admin_root_path

    assert_response :success
    assert_select ".admin-hub__wg", text: /WG\s*#{Regexp.escape(formatted_count)}/
  ensure
    Flipper.disable_actor(:show_wgs, @admin)
  end

  test "helper redirects to support dashboard" do
    sign_in @helper

    get admin_root_path

    assert_redirected_to admin_support_path
  end

  test "fraud reviewer redirects to fraud dashboard" do
    sign_in @fraud_reviewer

    get admin_root_path

    assert_redirected_to admin_fraud_path
  end

  test "admin role takes precedence over helper redirect" do
    admin_helper = create_user("admin_helper", :admin)
    admin_helper.grant_role!(:helper)

    sign_in admin_helper

    get admin_root_path

    assert_response :success
    assert_select "h1", text: /Admin/
  end

  private

  def create_user(label, role = nil)
    user = User.create!(
      slack_id: "U_ADMIN_HOME_#{label.upcase}",
      display_name: "admin_home_#{label}",
      email: "admin_home_#{label}@example.test"
    )

    user.grant_role!(role) if role
    user
  end
end
