require "test_helper"

class WorkshopsControllerTest < ActionDispatch::IntegrationTest
  # The workshop policies require a linked (non-guest) account, and
  # users(:three) has no hack_club identity fixture.
  def sign_in_linked_three
    users(:three).identities.create!(provider: "hack_club", uid: "workshop-test-three", access_token: "workshop-test-token")
    sign_in users(:three)
  end

  test "index requires sign in" do
    get workshops_path

    assert_redirected_to root_path
  end

  test "index lists upcoming and past workshops" do
    sign_in users(:one)

    get workshops_path

    assert_response :success
    assert_match workshops(:upcoming).title, response.body
    assert_match workshops(:ended).title, response.body
  end

  test "show requires sign in" do
    get workshop_path(workshops(:upcoming))

    assert_redirected_to root_path
  end

  test "show renders for a signed-in user" do
    sign_in users(:one)

    get workshop_path(workshops(:upcoming))

    assert_response :success
    assert_match workshops(:upcoming).title, response.body
  end

  test "rsvp create adds the user" do
    sign_in_linked_three
    workshop = workshops(:upcoming)

    assert_difference -> { workshop.rsvps.count }, 1 do
      post workshop_rsvp_path(workshop)
    end
    assert_redirected_to workshop_path(workshop)
  end

  test "rsvp create is idempotent" do
    sign_in users(:one)
    workshop = workshops(:upcoming)

    assert_no_difference -> { workshop.rsvps.count } do
      post workshop_rsvp_path(workshop)
    end
  end

  test "rsvp is refused after the workshop ended" do
    sign_in_linked_three
    workshop = workshops(:ended)

    assert_no_difference -> { workshop.rsvps.count } do
      post workshop_rsvp_path(workshop)
    end
    assert_equal "This workshop has already ended.", flash[:alert]
  end

  test "rsvp destroy removes the user's rsvp" do
    sign_in users(:one)
    workshop = workshops(:upcoming)

    assert_difference -> { workshop.rsvps.count }, -1 do
      delete workshop_rsvp_path(workshop)
    end
  end

  test "joining inside the window records attendance and redirects to zoom" do
    sign_in users(:two)
    workshop = workshops(:joinable)

    assert_difference -> { workshop.attendances.count }, 1 do
      post workshop_attendance_path(workshop)
    end
    assert_redirected_to workshop.zoom_link
  end

  test "joining twice records one attendance" do
    sign_in users(:two)
    workshop = workshops(:joinable)

    post workshop_attendance_path(workshop)
    assert_no_difference -> { workshop.attendances.count } do
      post workshop_attendance_path(workshop)
    end
    assert_redirected_to workshop.zoom_link
  end

  test "joining inside the window without a zoom link yet is refused" do
    sign_in users(:two)
    workshop = Workshop.create!(title: "Linkless", starts_at: 5.minutes.from_now, ends_at: 1.hour.from_now)

    assert_no_difference -> { workshop.attendances.count } do
      post workshop_attendance_path(workshop)
    end
    assert_redirected_to workshop_path(workshop)
  end

  test "joining before the window is refused" do
    sign_in users(:two)
    workshop = workshops(:upcoming)

    assert_no_difference -> { workshop.attendances.count } do
      post workshop_attendance_path(workshop)
    end
    assert_redirected_to workshop_path(workshop)
  end

  test "joining after the end is refused" do
    sign_in users(:two)
    workshop = workshops(:ended)

    assert_no_difference -> { workshop.attendances.count } do
      post workshop_attendance_path(workshop)
    end
    assert_redirected_to workshop_path(workshop)
  end
end
