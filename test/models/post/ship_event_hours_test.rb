require "test_helper"

# Covers the build-only / deflated payout basis introduced for the hardware
# funding flow. See Post::ShipEvent#hours.
class Post::ShipEventHoursTest < ActiveSupport::TestCase
  def setup
    Flipper.enable(:hardware_flow)
    @owner = User.create!(
      email: "owner-#{SecureRandom.hex(6)}@example.com",
      display_name: "Owner#{SecureRandom.hex(3)}",
      slack_id: "U#{SecureRandom.hex(8)}"
    )
  end

  test "software project counts every logged second (unchanged)" do
    project = Project.create!(title: "SW #{SecureRandom.hex(4)}", created_at: 3.days.ago)
    create_devlog(project, seconds: 3600, phase: nil, at: 2.days.ago)
    create_devlog(project, seconds: 3600, phase: nil, at: 1.day.ago)
    ship = create_ship(project)

    assert_in_delta 2.0, ship.reload.hours, 0.001
  end

  test "hardware project counts only build-phase devlogs" do
    project = Project.create!(title: "HW #{SecureRandom.hex(4)}", hardware_stage: "design", created_at: 3.days.ago)
    create_devlog(project, seconds: 3600, phase: "design", at: 2.days.ago) # unpaid
    project.update!(hardware_stage: "build")
    create_devlog(project, seconds: 7200, phase: "build", at: 1.day.ago)   # paid
    ship = create_ship(project)

    assert_in_delta 2.0, ship.reload.hours, 0.001
  end

  test "hardware project uses reviewer-approved (deflated) minutes when reviewed" do
    project = Project.create!(title: "HW #{SecureRandom.hex(4)}", hardware_stage: "build", created_at: 3.days.ago)
    build_devlog = create_devlog(project, seconds: 7200, phase: "build", at: 1.day.ago) # 120 logged minutes
    ship = create_ship(project)

    ysws = Certification::Ysws.create!(user: @owner, project: project, post_ship_event: ship, original_minutes: 120)
    Certification::Devlog
      .create!(post_devlog: build_devlog, ysws_review: ysws, original_minutes: 120, status: :pending)
      .approve!(60, "Timelapse looked padded")

    assert_in_delta 1.0, ship.reload.hours, 0.001
  end

  test "a rejected devlog review contributes zero" do
    project = Project.create!(title: "HW #{SecureRandom.hex(4)}", hardware_stage: "build", created_at: 3.days.ago)
    build_devlog = create_devlog(project, seconds: 7200, phase: "build", at: 1.day.ago)
    ship = create_ship(project)

    ysws = Certification::Ysws.create!(user: @owner, project: project, post_ship_event: ship, original_minutes: 120)
    Certification::Devlog
      .create!(post_devlog: build_devlog, ysws_review: ysws, original_minutes: 120, status: :pending)
      .reject!("Could not verify any of this time")

    assert_in_delta 0.0, ship.reload.hours, 0.001
  end

  private

  def create_devlog(project, seconds:, phase:, at:)
    devlog = Post::Devlog.new(body: "work log", duration_seconds: seconds, phase: phase)
    devlog.uploading_attachments = true
    devlog.save!
    Post.create!(project: project, user: @owner, postable: devlog, created_at: at)
    devlog
  end

  def create_ship(project)
    ship = Post::ShipEvent.new(body: "ship it")
    ship.uploading_attachments = true
    ship.save!
    Post.create!(project: project, user: @owner, postable: ship, created_at: Time.current)
    ship
  end
end
