require "test_helper"

class OneTime::BackfillIntegrityStatusAirtableSyncJobTest < ActiveJob::TestCase
  setup do
    @owner   = create_user(slack_id: "U#{SecureRandom.hex(8)}", display_name: "user#{SecureRandom.hex(4)}")
    @project = create_project
    @stale   = create_ysws_review(synced_at: 1.day.ago)
    @current = create_ysws_review(synced_at: 1.minute.from_now)
  end

  test "dry run reports the stale reviews and enqueues nothing" do
    assert_no_enqueued_jobs do
      assert_equal [ @stale.id ], OneTime::BackfillIntegrityStatusAirtableSyncJob.perform_now
    end
  end

  test "a wet run enqueues one sync per stale review" do
    review_ids = nil

    assert_enqueued_with(job: OneTime::SyncIntegrityStatusToAirtableJob, args: [ @stale.id ]) do
      review_ids = OneTime::BackfillIntegrityStatusAirtableSyncJob.perform_now(dry_run: false)
    end

    assert_equal [ @stale.id ], review_ids
    assert_enqueued_jobs 1, only: OneTime::SyncIntegrityStatusToAirtableJob
  end

  test "reviews that were never synced are out of scope" do
    @stale.update_column(:airtable_synced_at, nil)

    assert_empty OneTime::BackfillIntegrityStatusAirtableSyncJob.perform_now
  end

  test "reviews without an integrity check are out of scope" do
    @stale.integrity_check.destroy!

    assert_empty OneTime::BackfillIntegrityStatusAirtableSyncJob.perform_now
  end

  private

  def create_project
    Project.create!(title: "Project #{SecureRandom.hex(4)}").tap do |project|
      Project::Membership.create!(project: project, user: @owner, role: :owner)
    end
  end

  # A completed review with an integrity check touched at Time.current, so the
  # sync marker alone decides whether it is stale.
  def create_ysws_review(synced_at:)
    ship = Post::ShipEvent.new(body: "ship it")
    ship.uploading_attachments = true
    ship.save!
    Post.create!(project: @project, user: @owner, postable: ship)
    ::Certification::Integrity.create!(ship_event: ship, status: :pending)

    ::Certification::Ysws.create!(
      user: @owner,
      project: @project,
      post_ship_event: ship,
      original_minutes: 60,
      reviewer: @owner,
      reviewed_at: 2.days.ago,
      airtable_synced_at: synced_at
    )
  end
end
