require "test_helper"

class Admin::Certification::IntegrityControllerTest < ActionDispatch::IntegrationTest
  include UserFactory
  include FraudDetectionDataStub

  setup do
    @admin = create_user(slack_id: "U_INTEGRITY_ADMIN", display_name: "integrity_admin")
    @admin.grant_role!(:admin)

    @shipper = create_user(slack_id: "U_INTEGRITY_SHIPPER", display_name: "shipper")
    @project = Project.create!(title: "Shipped build")
    Project::Membership.create!(project: @project, user: @shipper, role: :owner)
    ship_event = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true)
    Post.create!(project: @project, user: @shipper, postable: ship_event)
    @review = ::Certification::Integrity.create!(ship_event: ship_event, status: :pending)
  end

  test "the queue holds a check back until the GOI has reviewed the ship" do
    sign_in @admin
    get admin_certification_integrity_reviews_path

    assert_response :success
    assert_select "a[href=?]", admin_certification_integrity_review_path(@review), count: 0

    Certification::Ysws.create!(user: @shipper, project: @project, post_ship_event: @review.ship_event,
                                original_minutes: 60, reviewed_at: Time.current)
    get admin_certification_integrity_reviews_path

    assert_select "a[href=?]", admin_certification_integrity_review_path(@review)
  end

  test "a GOI review sent back to the maker does not release the check" do
    Certification::Ysws.create!(user: @shipper, project: @project, post_ship_event: @review.ship_event,
                                original_minutes: 60, returned_at: Time.current)

    sign_in @admin
    get admin_certification_integrity_reviews_path

    assert_select "a[href=?]", admin_certification_integrity_review_path(@review), count: 0
  end

  test "the review page says so when nothing was detected" do
    sign_in @admin
    get admin_certification_integrity_review_path(@review)

    assert_response :success
    assert_match "Review reasoning", response.body
    assert_match "No detection data recorded", response.body
  end

  test "the review page lists the detection signals" do
    with_detection_data("percentage_of_something" => 0.42) do
      sign_in @admin
      get admin_certification_integrity_review_path(@review)
    end

    assert_response :success
    assert_match "Percentage of something", response.body
    assert_match "42.0%", response.body
  end
end
