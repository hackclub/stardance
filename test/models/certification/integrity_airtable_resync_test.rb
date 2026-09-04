require "test_helper"

# The Airtable submission payload is written once, when a reviewer completes the
# YSWS review. Integrity verdicts land on their own clock and usually arrive
# afterwards, so the verdict has to push the payload back out itself.
class Certification::IntegrityAirtableResyncTest < ActiveSupport::TestCase
  include UserFactory
  include ActiveJob::TestHelper

  SYNC_JOB = Certification::YswsAirtableSyncJob

  setup { @user = create_user(slack_id: "u-integrity", display_name: "shipper") }

  test "a verdict resyncs the completed review on that ship event" do
    review = completed_review
    check = Certification::Integrity.create!(ship_event: review.post_ship_event, status: :pending)

    assert_enqueued_with(job: SYNC_JOB, args: [ review.id ]) do
      check.update!(status: :manually_passed, reviewer: @user)
    end
  end

  test "a deduction resyncs so the override hours lose the deducted minutes" do
    review = completed_review
    check = Certification::Integrity.create!(ship_event: review.post_ship_event, status: :pending)

    assert_enqueued_with(job: SYNC_JOB, args: [ review.id ]) do
      check.update!(status: :deducted, deduction_minutes: 45, reviewer: @user)
    end
  end

  test "a check arriving after completion syncs on creation" do
    review = completed_review

    assert_enqueued_with(job: SYNC_JOB, args: [ review.id ]) do
      Certification::Integrity.create!(ship_event: review.post_ship_event, status: :auto_passed)
    end
  end

  test "a review still in the queue is left for its own completion to sync" do
    review = pending_review
    check = Certification::Integrity.create!(ship_event: review.post_ship_event, status: :pending)

    assert_no_enqueued_jobs(only: SYNC_JOB) do
      check.update!(status: :manually_passed, reviewer: @user)
    end
  end

  test "a submission the unified base already holds is left for manual correction" do
    review = completed_review
    review.update_column(:in_unified_db, "recStubUnified01")
    check = Certification::Integrity.create!(ship_event: review.post_ship_event, status: :pending)

    assert_no_enqueued_jobs(only: SYNC_JOB) do
      check.update!(status: :deducted, deduction_minutes: 30, reviewer: @user)
    end
  end

  test "a ship event with no review enqueues nothing" do
    _project, ship_event = project_with_ship
    check = Certification::Integrity.create!(ship_event: ship_event, status: :pending)

    assert_no_enqueued_jobs(only: SYNC_JOB) do
      check.update!(status: :manually_passed, reviewer: @user)
    end
  end

  test "a sibling the cascade rewrites resyncs its own review" do
    project, first_ship = project_with_ship
    second_ship = ship_on(project)
    sibling_review = completed_review(project: project, ship_event: second_ship)

    Certification::Integrity.create!(ship_event: second_ship, status: :pending)
    decided = Certification::Integrity.create!(ship_event: first_ship, status: :pending)

    assert_enqueued_with(job: SYNC_JOB, args: [ sibling_review.id ]) do
      decided.update!(status: :banned, reviewer: @user)
    end
  end

  private

  def project_with_ship
    project = Project.create!(title: "Ship #{SecureRandom.hex(4)}")
    Project::Membership.create!(project: project, user: @user, role: :owner)
    [ project, ship_on(project) ]
  end

  # Built before the Post exists so Post::ShipEvent's shippability validation has
  # no project to check, matching how the other ship-event suites do it.
  def ship_on(project)
    ship_event = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true)
    Post.create!(project: project, user: @user, postable: ship_event)
    ship_event
  end

  def completed_review(project: nil, ship_event: nil)
    project, ship_event = project_with_ship if project.nil?

    Certification::Ysws.create!(
      user: @user,
      project: project,
      post_ship_event: ship_event,
      original_minutes: 120,
      reviewer: @user,
      reviewed_at: Time.current,
      airtable_synced_at: Time.current
    )
  end

  def pending_review
    project, ship_event = project_with_ship

    Certification::Ysws.create!(
      user: @user,
      project: project,
      post_ship_event: ship_event,
      original_minutes: 120
    )
  end
end
