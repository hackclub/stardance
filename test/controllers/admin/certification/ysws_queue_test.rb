require "test_helper"

# The GOI goes first, so its queue lists every pending review. Integrity waits on
# the GOI instead (Certification::Integrity.past_goi).
class Admin::Certification::YswsQueueTest < ActionDispatch::IntegrationTest
  include UserFactory

  setup do
    @admin = create_user(slack_id: "U_YSWS_QUEUE_ADMIN", display_name: "ysws_queue_admin")
    @admin.grant_role!(:admin)
    @shipper = create_user(slack_id: "U_YSWS_QUEUE_SHIPPER", display_name: "ysws_queue_shipper")
  end

  test "a review whose integrity check is still pending is in the queue" do
    review = pending_review(integrity: :pending)

    sign_in @admin
    get admin_certification_ysws_reviews_path

    assert_response :success
    assert_select "a[href=?]", admin_certification_ysws_review_path(review)
  end

  test "a review with no integrity check yet is in the queue" do
    review = pending_review(integrity: nil)

    sign_in @admin
    get admin_certification_ysws_reviews_path

    assert_select "a[href=?]", admin_certification_ysws_review_path(review)
  end

  test "the old integrity-only toggle is gone" do
    pending_review(integrity: :pending)

    sign_in @admin
    get admin_certification_ysws_reviews_path(with_integrity: "1")

    assert_response :success
    assert_select "#filter-with-integrity", count: 0
  end

  test "review flow includes reviews still waiting on integrity" do
    review = pending_review(integrity: :pending)
    Flipper.enable(:ysws_review_flow, @admin)

    sign_in @admin
    post next_admin_certification_ysws_reviews_path, params: { flow: 1, step: 1 }

    assert_redirected_to admin_certification_ysws_review_path(review, flow: 1, step: 1)
    assert review.reload.claimed_by?(@admin)
    version = review.versions.where(event: "claim").sole
    assert_equal @admin.id.to_s, version.whodunnit
    assert_equal [ nil, @admin.id ], version.changeset["claimed_by_id"]
    assert_in_delta review.claimed_at.to_f, Time.zone.parse(version.changeset["claimed_at"].last).to_f, 0.001
  ensure
    Flipper.disable(:ysws_review_flow, @admin)
  end

  test "review flow respects the queue age sort" do
    older = pending_review(integrity: nil)
    newer = pending_review(integrity: nil)
    older.update!(created_at: 2.days.ago)
    newer.update!(created_at: 1.day.ago)
    Flipper.enable(:ysws_review_flow, @admin)

    sign_in @admin
    get admin_certification_ysws_reviews_path(sort: "age", dir: "desc")
    post next_admin_certification_ysws_reviews_path, params: { flow: 1, step: 1 }

    assert_redirected_to admin_certification_ysws_review_path(newer, flow: 1, step: 1)
  ensure
    Flipper.disable(:ysws_review_flow, @admin)
  end

  test "skipping project 99 advances to project 100 and audits the claim" do
    review = pending_review(integrity: nil)
    following = pending_review(integrity: nil)
    Flipper.enable(:ysws_review_flow, @admin)
    Certification::Ysws.atomic_claim!(review.id, @admin)

    sign_in @admin
    post skip_admin_certification_ysws_review_path(review), params: { flow: 1, step: 99 }

    assert_redirected_to admin_certification_ysws_review_path(following, flow: 1, step: 100, skip: review.id.to_s)
    assert_nil review.reload.claimed_by_id
    assert following.reload.claimed_by?(@admin)
    assert_equal @admin.id.to_s, following.versions.where(event: "claim").sole.whodunnit
  ensure
    Flipper.disable(:ysws_review_flow, @admin)
  end

  test "skipping project 100 ends the flow without claiming another review" do
    review = pending_review(integrity: nil)
    following = pending_review(integrity: nil)
    Flipper.enable(:ysws_review_flow, @admin)
    Certification::Ysws.atomic_claim!(review.id, @admin)

    sign_in @admin
    post skip_admin_certification_ysws_review_path(review), params: { flow: 1, step: 100 }

    assert_redirected_to admin_certification_ysws_reviews_path
    assert_includes flash[:notice], "100-project limit"
    assert_nil review.reload.claimed_by_id
    assert_nil following.reload.claimed_by_id
    assert_empty following.versions.where(event: "claim")
  ensure
    Flipper.disable(:ysws_review_flow, @admin)
  end

  test "completing project 100 ends the flow without claiming another review" do
    review = pending_review(integrity: nil)
    following = pending_review(integrity: nil)
    Flipper.enable(:ysws_review_flow, @admin)
    Certification::Ysws.atomic_claim!(review.id, @admin)

    sign_in @admin
    Certification::YswsAirtable.stub(:record_for, nil) do
      assert_enqueued_with(job: Certification::YswsAirtableSyncJob, args: [ review.id ]) do
        post complete_admin_certification_ysws_review_path(review), params: { flow: 1, step: 100 }
      end
    end

    assert_redirected_to admin_certification_ysws_reviews_path
    assert_includes flash[:notice], "100-project limit"
    assert review.reload.reviewed_at.present?
    assert_nil following.reload.claimed_by_id
    assert_empty following.versions.where(event: "claim")
  ensure
    Flipper.disable(:ysws_review_flow, @admin)
  end

  test "an unsuccessful claim does not record an audit event" do
    review = pending_review(integrity: nil)
    Certification::Ysws.atomic_claim!(review.id, @shipper)

    assert_no_difference -> { review.versions.count } do
      assert_nil Certification::Ysws.atomic_claim!(review.id, @admin)
    end
    assert review.reload.claimed_by?(@shipper)
  end

  private

  def pending_review(integrity:)
    project = Project.create!(title: "GOI queue #{SecureRandom.hex(4)}")
    Project::Membership.create!(project: project, user: @shipper, role: :owner)
    ship_event = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true)
    Post.create!(project: project, user: @shipper, postable: ship_event)
    Certification::Integrity.create!(ship_event: ship_event, status: integrity) if integrity
    Certification::Ysws.create!(user: @shipper, project: project, post_ship_event: ship_event, original_minutes: 60)
  end
end
