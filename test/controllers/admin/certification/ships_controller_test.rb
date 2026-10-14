require "test_helper"

# Hardware ships are certified in the hardware build queue, so they must not
# reach the shipwright ship queue — the same rows back both listings.
class Admin::Certification::ShipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @reviewer = create_user(slack_id: "U_SHIPQ_REV", display_name: "shipq-reviewer")
    @reviewer.grant_role!(:project_certifier)

    @owner = create_user(slack_id: "U_SHIPQ_OWNER", display_name: "shipq-owner")

    @software = project("Software ship")
    @software_ship = ::Certification::Ship.create!(project: @software, status: :pending)

    @hardware = project("Hardware ship")
    @hardware.update!(hardware_stage: "build")
    @hardware_ship = ::Certification::Ship.create!(project: @hardware, status: :pending)

    sign_in @reviewer
  end

  test "the ship queue lists software ships and hides hardware ones" do
    get admin_certification_ships_path

    assert_response :success
    assert_select ".ship-queue__project-title", text: /Software ship/
    assert_select ".ship-queue__project-title", text: /Hardware ship/, count: 0
  end

  # The header count comes from dashboard_stats while the rows come from the
  # policy scope; if only one of them learns to skip hardware the page shows a
  # backlog the reviewer can't see.
  test "the queue-health count matches the rows on the page" do
    get admin_certification_ships_path

    assert_response :success
    assert_select ".ship-queue__metric-value", text: /\A\s*1\s*\z/
    assert_select ".ship-queue__table .ship-queue__project-title", count: 1
  end

  test "the review logs hide decided hardware ships" do
    @software_ship.update!(reviewer: @reviewer, status: :approved)
    @hardware_ship.update!(reviewer: @reviewer, status: :approved)

    get logs_admin_certification_ships_path

    assert_response :success
    assert_select ".ship-queue__project-title", text: /Software ship/
    assert_select ".ship-queue__project-title", text: /Hardware ship/, count: 0
  end

  test "claiming the next review never hands over a hardware ship" do
    get next_admin_certification_ships_path

    assert_redirected_to admin_certification_ship_path(@software_ship)

    # With only hardware left the software queue reads as empty rather than
    # falling through to a build cert. Reload first: the claim above bumped
    # lock_version straight in the database.
    @software_ship.reload.update!(reviewer: @reviewer, status: :approved)
    get next_admin_certification_ships_path

    assert_redirected_to admin_certification_ships_path
    assert_equal "Queue is empty.", flash[:notice]
  end

  private

  def project(title)
    project = Project.create!(title: title, description: "A ship", ship_status: "submitted")
    project.memberships.create!(user: @owner, role: :owner)
    project
  end
end
