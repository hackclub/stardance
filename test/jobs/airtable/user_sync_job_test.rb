require "test_helper"

class Airtable::UserSyncJobTest < ActiveSupport::TestCase
  setup do
    @user = create_user(slack_id: "U#{SecureRandom.hex(8)}", display_name: "star#{SecureRandom.hex(4)}")
  end

  test "field_mapping surfaces the latest ship-event payout as Loops properties" do
    # An older payout that should be superseded by the newer one below.
    older = create_ship_event_payout(title: "Nebula Sampler", amount: 10)
    older.update_column(:created_at, 3.days.ago)

    newer = create_ship_event_payout(title: "Aurora Probe", amount: 42)

    fields = Airtable::UserSyncJob.new.field_mapping(@user)

    assert_equal newer.created_at.iso8601, fields["Loops - stardancePayoutIssuedAt"]
    assert_equal 42, fields["Loops - stardancePayoutStardust"]
    assert_equal "Aurora Probe", fields["Loops - stardancePayoutProject"]
  end

  test "field_mapping omits payout properties when the user has no ship-event payout" do
    # A non-ship-event ledger entry must not trigger the payout fields.
    @user.ledger_entries.create!(ledgerable: @user, amount: 5, reason: "Some other credit", created_by: "test")

    fields = Airtable::UserSyncJob.new.field_mapping(@user)

    assert_not fields.key?("Loops - stardancePayoutIssuedAt")
    assert_not fields.key?("Loops - stardancePayoutStardust")
    assert_not fields.key?("Loops - stardancePayoutProject")
  end

  test "field_mapping lists the free sticker weeks the user shipped in" do
    project = Project.create!(title: "Sticker Chaser")
    Project::Membership.create!(project: project, user: @user, role: :owner)
    ship_event = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true)
    post = Post.create!(project: project, user: @user, postable: ship_event)
    post.update_column(:created_at, StickerPromo::WEEKS.last.window_start + 1.hour)

    fields = Airtable::UserSyncJob.new.field_mapping(@user)

    assert_equal StickerPromo::WEEKS.last.number.to_s, fields["Loops - stardanceWeeklyStickerEmail"]
  end

  test "field_mapping sends a blank free sticker weeks value when the user earned none" do
    fields = Airtable::UserSyncJob.new.field_mapping(@user)

    assert_equal "", fields["Loops - stardanceWeeklyStickerEmail"]
  end

  test "field_mapping surfaces the biggest unshipped project at the user's past payout rate" do
    rocket = create_owned_project("Rocket Garden")
    create_devlog(rocket, seconds: 2.hours, at: 5.days.ago)
    create_paid_ship(rocket, payout: 100, hours_at_payout: 10, at: 4.days.ago)
    # Only time since the last ship counts, each devlog capped like a payout.
    create_devlog(rocket, seconds: 12.hours, at: 2.days.ago)
    create_devlog(rocket, seconds: 1.hour, at: 1.day.ago)

    create_devlog(create_owned_project("Comet Notes"), seconds: 3.hours, at: 1.day.ago)

    fields = Airtable::UserSyncJob.new.field_mapping(@user)

    assert_equal "Rocket Garden", fields["Loops - stardanceUnshippedProject"]
    assert_equal 11.0, fields["Loops - stardanceUnshippedHours"]
    assert_equal 110, fields["Loops - stardanceUnshippedStardust"]
    assert_equal 1, fields["Loops - stardanceUnshippedOtherProjects"]
  end

  test "field_mapping adds today's Finality bonus to the unshipped estimate" do
    travel_to Time.find_zone!(Finality::TIME_ZONE).local(2026, 10, 28, 12) do
      Flipper.enable(Finality::FEATURE_FLAG)
      project = create_owned_project("Late Launch")
      create_paid_ship(project, payout: 100, hours_at_payout: 10, at: 3.days.ago)
      create_devlog(project, seconds: 10.hours, at: 1.day.ago)

      fields = Airtable::UserSyncJob.new.field_mapping(@user)

      assert_equal 106, fields["Loops - stardanceUnshippedStardust"]
    ensure
      Flipper.disable(Finality::FEATURE_FLAG)
    end
  end

  test "field_mapping sends blank unshipped properties when everything is shipped" do
    project = create_owned_project("All Shipped")
    create_devlog(project, seconds: 2.hours, at: 2.days.ago)
    create_paid_ship(project, payout: 20, hours_at_payout: 2, at: 1.day.ago)

    fields = Airtable::UserSyncJob.new.field_mapping(@user)

    assert fields.key?("Loops - stardanceUnshippedProject")
    assert_nil fields["Loops - stardanceUnshippedProject"]
    assert_nil fields["Loops - stardanceUnshippedHours"]
    assert_nil fields["Loops - stardanceUnshippedStardust"]
    assert_nil fields["Loops - stardanceUnshippedOtherProjects"]
  end

  private

  def create_owned_project(title)
    project = Project.create!(title: title)
    Project::Membership.create!(project: project, user: @user, role: :owner)
    project
  end

  def create_devlog(project, seconds:, at:)
    devlog = Post::Devlog.new(body: "work log", duration_seconds: seconds)
    devlog.uploading_attachments = true
    devlog.save!
    Post.create!(project: project, user: @user, postable: devlog, created_at: at)
  end

  def create_paid_ship(project, payout:, hours_at_payout:, at:)
    ship_event = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true)
    Post.create!(project: project, user: @user, postable: ship_event, created_at: at)
    ship_event.update_columns(payout: payout, hours_at_payout: hours_at_payout)
  end

  def create_ship_event_payout(title:, amount:)
    project = Project.create!(title: title, created_at: 3.days.ago)
    ship_event = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true)
    Post.create!(project: project, user: @user, postable: ship_event)
    @user.ledger_entries.create!(
      ledgerable: ship_event,
      amount: amount,
      reason: "Ship event payout: #{title}",
      created_by: "ship_event_payout"
    )
  end
end
