require "test_helper"

# GOI, then integrity, then Airtable: a completed review waits for its ship's
# integrity verdict before it syncs, so the hours sent are the final ones.
class Certification::YswsAirtableSyncJobGateTest < ActiveSupport::TestCase
  include UserFactory

  FakeTable = Struct.new(:upserts) do
    def upsert(fields, key) = upserts << [ fields, key ]
  end

  setup { @user = create_user(slack_id: "u-sync-gate", display_name: "syncgate") }

  test "a review waiting on a pending integrity check does not sync" do
    review = completed_review
    Certification::Integrity.create!(ship_event: review.post_ship_event, status: :pending)

    assert_empty run_sync(review)
    assert_nil review.reload.airtable_synced_at
  end

  test "a review whose ship has no integrity check yet does not sync" do
    review = completed_review

    assert_empty run_sync(review)
    assert_nil review.reload.airtable_synced_at
  end

  test "a review syncs once the integrity verdict is in" do
    review = completed_review
    Certification::Integrity.create!(ship_event: review.post_ship_event, status: :manually_passed, reviewer: @user)

    assert_equal 1, run_sync(review).size
    assert_not_nil review.reload.airtable_synced_at
  end

  test "a hardware review syncs without an integrity check, since hardware skips integrity" do
    review = completed_review
    review.project.update_column(:hardware_stage, Project::HARDWARE_STAGES.first)

    assert_equal 1, run_sync(review).size
  end

  private

  def run_sync(review)
    table = FakeTable.new([])
    job = Certification::YswsAirtableSyncJob.new
    job.stub(:check_stardance_review_submitted_unified, nil) do
      job.stub(:check_user_status, { rejected: false }) do
        job.stub(:build_airtable_fields, { "review_id" => review.id.to_s }) do
          job.stub(:table, table) { job.perform(review.id) }
        end
      end
    end
    table.upserts
  end

  def completed_review
    project = Project.create!(title: "Sync gate #{SecureRandom.hex(4)}")
    Project::Membership.create!(project: project, user: @user, role: :owner)
    ship_event = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true)
    Post.create!(project: project, user: @user, postable: ship_event)
    Certification::Ysws.create!(user: @user, project: project, post_ship_event: ship_event,
                                original_minutes: 120, reviewer: @user, reviewed_at: Time.current)
  end
end
