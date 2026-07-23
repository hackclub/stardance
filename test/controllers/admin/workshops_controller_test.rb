require "test_helper"

class Admin::WorkshopsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(slack_id: "U_WS_ADMIN", display_name: "ws_admin", email: "ws_admin@example.test")
    @admin.grant_role!(:admin)

    @manager = User.create!(slack_id: "U_WS_MANAGER", display_name: "ws_manager", email: "ws_manager@example.test")
    @manager.grant_role!(:workshop_manager)
  end

  test "admin sees the workshop list" do
    sign_in @admin

    get admin_workshops_path

    assert_response :success
    assert_match workshops(:upcoming).title, response.body
  end

  test "workshop manager sees the workshop list" do
    sign_in @manager

    get admin_workshops_path

    assert_response :success
  end

  test "regular user is denied" do
    sign_in users(:one)

    get admin_workshops_path

    assert_response :not_found
  end

  test "admin root redirects a workshop manager to workshops" do
    sign_in @manager

    get admin_root_path

    assert_redirected_to admin_workshops_path
  end

  test "workshop manager can create a workshop" do
    sign_in @manager
    starts_at = 4.days.from_now.change(usec: 0)

    assert_difference -> { Workshop.count }, 1 do
      post admin_workshops_path, params: {
        workshop: {
          title: "Terminal games 101",
          description: "Build a TUI game.",
          zoom_link: "https://zoom.us/j/42",
          starts_at: starts_at,
          ends_at: starts_at + 1.hour
        }
      }
    end

    workshop = Workshop.order(:id).last
    assert_redirected_to admin_workshop_path(workshop)
    assert_equal @manager.id.to_s, workshop.versions.last.whodunnit
  end

  test "form times are interpreted as Eastern time" do
    sign_in @admin

    post admin_workshops_path, params: {
      workshop: { title: "TZ check", starts_at: "2026-08-03T15:00", ends_at: "2026-08-03T16:00" }
    }

    workshop = Workshop.order(:id).last
    assert_equal Time.utc(2026, 8, 3, 19, 0), workshop.starts_at
    assert_equal Time.utc(2026, 8, 3, 20, 0), workshop.ends_at
  end

  test "invalid workshop re-renders the form" do
    sign_in @admin

    assert_no_difference -> { Workshop.count } do
      post admin_workshops_path, params: { workshop: { title: "", zoom_link: "nope" } }
    end
    assert_response :unprocessable_entity
  end

  test "admin can update a workshop" do
    sign_in @admin
    workshop = workshops(:upcoming)

    patch admin_workshop_path(workshop), params: { workshop: { title: "Renamed" } }

    assert_redirected_to admin_workshop_path(workshop)
    assert_equal "Renamed", workshop.reload.title
  end

  test "admin can destroy a workshop" do
    sign_in @admin

    assert_difference -> { Workshop.count }, -1 do
      delete admin_workshop_path(workshops(:ended))
    end
    assert_redirected_to admin_workshops_path
  end

  test "show lists rsvps and attendees" do
    sign_in @admin

    get admin_workshop_path(workshops(:upcoming))

    assert_response :success
    assert_match users(:one).display_name, response.body
  end
end
