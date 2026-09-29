require "test_helper"

# Covers the build-only / deflated payout basis introduced for the hardware
# funding flow. See Post::ShipEvent#hours.
class Post::ShipEventHoursTest < ActiveSupport::TestCase
  def setup
    Flipper.enable(:hardware_flow)
    @owner = User.create!(
      email: "owner-#{SecureRandom.hex(6)}@example.com",
      display_name: "Owner#{SecureRandom.hex(3)}",
      slack_id: "U#{SecureRandom.hex(8)}",
      verification_status: :verified, ysws_eligible: true
    )
  end

  test "software project counts every logged second (unchanged)" do
    project = Project.create!(title: "SW #{SecureRandom.hex(4)}", created_at: 3.days.ago)
    create_devlog(project, seconds: 3600, phase: nil, at: 2.days.ago)
    create_devlog(project, seconds: 3600, phase: nil, at: 1.day.ago)
    ship = create_ship(project)

    assert_in_delta 2.0, ship.reload.hours_at_ship, 0.001
    assert_in_delta 2.0, ship.hours, 0.001
  end

  test "hardware project counts only build-phase devlogs" do
    project = Project.create!(title: "HW #{SecureRandom.hex(4)}", hardware_stage: "design", created_at: 3.days.ago)
    create_devlog(project, seconds: 3600, phase: "design", at: 2.days.ago) # unpaid
    project.update!(hardware_stage: "build")
    create_devlog(project, seconds: 7200, phase: "build", at: 1.day.ago)   # paid
    ship = create_ship(project)

    assert_in_delta 2.0, ship.reload.hours_at_ship, 0.001
    assert_in_delta 2.0, ship.hours, 0.001
  end

  test "hardware project uses reviewer-approved (deflated) minutes when reviewed" do
    project = Project.create!(title: "HW #{SecureRandom.hex(4)}", hardware_stage: "build", created_at: 3.days.ago)
    build_devlog = create_devlog(project, seconds: 7200, phase: "build", at: 1.day.ago) # 120 logged minutes
    ship = create_ship(project)

    ysws = Certification::Ysws.create!(user: @owner, project: project, post_ship_event: ship, original_minutes: 120)
    Certification::Devlog
      .create!(post_devlog: build_devlog, ysws_review: ysws, original_minutes: 120, status: :pending)
      .approve!(60, "Timelapse looked padded")

    assert_in_delta 2.0, ship.reload.hours_at_ship, 0.001
    assert_in_delta 1.0, ship.hours, 0.001
  end

  test "a rejected devlog review contributes zero" do
    project = Project.create!(title: "HW #{SecureRandom.hex(4)}", hardware_stage: "build", created_at: 3.days.ago)
    build_devlog = create_devlog(project, seconds: 7200, phase: "build", at: 1.day.ago)
    ship = create_ship(project)

    ysws = Certification::Ysws.create!(user: @owner, project: project, post_ship_event: ship, original_minutes: 120)
    Certification::Devlog
      .create!(post_devlog: build_devlog, ysws_review: ysws, original_minutes: 120, status: :pending)
      .reject!("Could not verify any of this time")

    assert_in_delta 2.0, ship.reload.hours_at_ship, 0.001
    assert_in_delta 0.0, ship.hours, 0.001
  end

  # --- software-origin conversions --------------------------------------------

  # A project built as software (phase-less devlogs) that turned hardware without
  # ever asking for funding used to pay nothing: none of its time was tagged
  # "build". Its software time isn't design work, so it counts from the start.
  test "a converted project with no funding counts its software time" do
    project = Project.create!(title: "HW #{SecureRandom.hex(4)}", created_at: 5.days.ago)
    create_devlog(project, seconds: 7200, phase: nil, at: 3.days.ago) # logged as software
    project.update!(hardware_stage: "build")
    ship = create_ship(project)

    assert_in_delta 2.0, ship.reload.hours_at_ship, 0.001
    assert_in_delta 2.0, ship.hours, 0.001
  end

  # Once the convert has a funding request, the same funding boundary applies:
  # software time logged before it is pre-funding and doesn't count.
  test "a converted project with funding still respects the funding boundary" do
    project = hardware_project_with_approved_funding(requested_at: 2.days.ago)
    software = create_devlog(project, seconds: 7200, phase: nil, at: 4.days.ago)
    build    = create_devlog(project, seconds: 7200, phase: "build", at: 1.day.ago)
    software.update_column(:created_at, 4.days.ago)
    build.update_column(:created_at, 1.day.ago)
    ship = create_ship(project)

    # Only the post-funding build devlog counts: 2h, not 4h.
    assert_in_delta 2.0, ship.reload.hours, 0.001
  end

  # --- funding-request cutoff -------------------------------------------------

  test "hardware payout ignores reviewed time logged before the funding request" do
    project = hardware_project_with_approved_funding(requested_at: 2.days.ago)
    before = create_devlog(project, seconds: 7200, phase: "build", at: 3.days.ago)
    after  = create_devlog(project, seconds: 7200, phase: "build", at: 1.day.ago)
    before.update_column(:created_at, 3.days.ago)
    after.update_column(:created_at, 1.day.ago)
    ship = create_ship(project)

    review_devlogs(project, ship, { before => 120, after => 120 })

    # Only the devlog logged after the request counts: 120 minutes, not 240.
    assert_in_delta 2.0, ship.reload.hours, 0.001
  end

  test "a hardware project that skipped funding keeps all its reviewed time" do
    project = Project.create!(title: "HW #{SecureRandom.hex(4)}", hardware_stage: "build", created_at: 5.days.ago)
    old = create_devlog(project, seconds: 7200, phase: "build", at: 4.days.ago)
    old.update_column(:created_at, 4.days.ago)
    ship = create_ship(project)

    review_devlogs(project, ship, { old => 120 })

    assert_in_delta 2.0, ship.reload.hours, 0.001
  end

  # The reviewed branch only runs when a YSWS review exists. Without one the
  # hours come from raw devlog durations, which needs the same cutoff or a
  # funded build is paid for its pre-funding design time.
  test "the funding cutoff also applies when no reviewer has scored the devlogs" do
    project = hardware_project_with_approved_funding(requested_at: 2.days.ago)
    before = create_devlog(project, seconds: 7200, phase: "build", at: 3.days.ago)
    after  = create_devlog(project, seconds: 7200, phase: "build", at: 1.day.ago)
    before.update_column(:created_at, 3.days.ago)
    after.update_column(:created_at, 1.day.ago)
    ship = create_ship(project)

    # No Certification::Ysws review at all, so this takes the raw-duration path.
    assert_nil ship.reload.certification_ysws_review
    assert_in_delta 2.0, ship.hours, 0.001
  end

  # --- flat rate --------------------------------------------------------------

  test "an approved hardware build pays the flat rate per hour" do
    project = hardware_project_with_approved_funding(requested_at: 2.days.ago)
    devlog = create_devlog(project, seconds: 7200, phase: "build", at: 1.day.ago)
    devlog.update_column(:created_at, 1.day.ago)
    ship = create_ship(project)
    review_devlogs(project, ship, { devlog => 120 })

    assert_equal Post::ShipEvent::Payouts::HARDWARE_STARDUST_PER_HOUR,
                 ship.reload.send(:payout_multiplier)
  end

  test "software still uses the vote-percentile curve" do
    project = Project.create!(title: "SW #{SecureRandom.hex(4)}", created_at: 3.days.ago)
    create_devlog(project, seconds: 3600, phase: nil, at: 1.day.ago)
    ship = create_ship(project)

    assert_not ship.reload.send(:hardware_payout?)
  end

  test "a locked hardware snapshot records which rule paid it" do
    project = hardware_project_with_approved_funding(requested_at: 2.days.ago)
    devlog = create_devlog(project, seconds: 7200, phase: "build", at: 1.day.ago)
    devlog.update_column(:created_at, 1.day.ago)
    ship = create_ship(project)
    review_devlogs(project, ship, { devlog => 120 })

    assert ship.reload.send(:hardware_payout?)
    assert_equal "stardance_hardware_flat_5_v1", Post::ShipEvent::Payouts::HARDWARE_PAYOUT_CURVE_VERSION
  end

  test "window hours count only the time logged since the previous ship" do
    project = Project.create!(title: "SW #{SecureRandom.hex(4)}", created_at: 5.days.ago)
    create_devlog(project, seconds: 7200, phase: nil, at: 4.days.ago)
    first_ship = create_ship(project, at: 3.days.ago)
    create_devlog(project, seconds: 3600, phase: nil, at: 2.days.ago)
    second_ship = create_ship(project, at: 1.day.ago)

    assert_in_delta 2.0, first_ship.reload.window_hours, 0.001
    assert_in_delta 1.0, second_ship.reload.window_hours, 0.001
    assert_in_delta 3.0, project.reload.duration_seconds / 3600.0, 0.001
  end

  test "window hours survive a soft-deleted project" do
    project = Project.create!(title: "SW #{SecureRandom.hex(4)}", created_at: 3.days.ago)
    create_devlog(project, seconds: 3600, phase: nil, at: 2.days.ago)
    ship = create_ship(project)
    project.update!(deleted_at: Time.current)

    assert_nil ship.reload.project
    assert_in_delta 1.0, ship.window_hours, 0.001
  end

  private

  def hardware_project_with_approved_funding(requested_at:)
    project = Project.create!(title: "HW #{SecureRandom.hex(4)}", hardware_stage: "design", created_at: 5.days.ago)
    Project::Membership.create!(project: project, user: @owner, role: :owner)
    seed = create_devlog(project, seconds: 1200, phase: "design", at: requested_at)
    request = project.certification_funding_requests.create!(
      user: @owner, complexity_tier: 1, requested_amount_cents: 2_000, status: :pending
    )
    request.update_column(:created_at, requested_at)
    request.update_column(:status, ::Certification::FundingRequest.statuses[:approved])
    seed.update_column(:created_at, requested_at - 1.hour)
    project.update!(hardware_stage: "build")
    project
  end

  # Approves each devlog for the given minutes through the YSWS review.
  def review_devlogs(project, ship, minutes_by_devlog)
    total = minutes_by_devlog.values.sum
    ysws = Certification::Ysws.create!(user: @owner, project: project, post_ship_event: ship, original_minutes: total)
    minutes_by_devlog.each do |devlog, minutes|
      Certification::Devlog
        .create!(post_devlog: devlog, ysws_review: ysws, original_minutes: minutes, status: :pending)
        .approve!(minutes, "Verified against the timelapse")
    end
    ysws
  end

  def create_devlog(project, seconds:, phase:, at:)
    devlog = Post::Devlog.new(body: "work log", duration_seconds: seconds, phase: phase)
    devlog.uploading_attachments = true
    devlog.save!
    Post.create!(project: project, user: @owner, postable: devlog, created_at: at)
    devlog
  end

  def create_ship(project, at: Time.current)
    ship = Post::ShipEvent.new(body: "ship it")
    ship.uploading_attachments = true
    ship.save!
    Post.create!(project: project, user: @owner, postable: ship, created_at: at)
    ship
  end
end
