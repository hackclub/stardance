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

  private

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
