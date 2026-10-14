require "test_helper"

class Projects::RecertificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Flipper.enable(:hardware_action_items)

    @owner = create_user(slack_id: "U_REC_OWNER", display_name: "rec-owner", verified: true)
    # The action-item gate is hardware-only, so the gated tests below need a
    # hardware project — as the "Returned build" name always intended.
    @project = Project.create!(title: "Returned build", hardware_stage: "build")
    @project.memberships.create!(user: @owner, role: :owner)
    @project.update!(ship_status: "needs_changes")

    sign_in @owner
  end

  teardown { Flipper.disable(:hardware_action_items) }

  test "a recert that ticks nothing is refused" do
    returned_review(feedback: "nearly there\n- photograph the solder joints")

    assert_no_difference -> { @project.ship_reviews.count } do
      post project_recertification_path(@project)
    end

    assert_equal "needs_changes", @project.reload.ship_status
  end

  test "a recert that ticks every action item goes through" do
    review = returned_review(feedback: "nearly there\n- photograph the solder joints")

    assert_difference -> { @project.ship_reviews.count }, 1 do
      post project_recertification_path(@project), params: acknowledging(review, indices: [ 0 ])
    end

    assert_equal "submitted", @project.reload.ship_status
  end

  test "a recert that ticks only some action items is refused" do
    review = returned_review(feedback: "nearly there\n- photograph the solder joints\n- label the wires")

    assert_no_difference -> { @project.ship_reviews.count } do
      post project_recertification_path(@project), params: acknowledging(review, indices: [ 0 ])
    end

    assert_equal "needs_changes", @project.reload.ship_status
  end

  test "a recert fingerprinted against superseded feedback is refused" do
    review = returned_review(feedback: "nearly there\n- photograph the solder joints")
    params = acknowledging(review, indices: [ 0 ])
    review.update!(feedback: "nearly there\n- photograph the solder joints\n- and label the wires")

    assert_no_difference -> { @project.ship_reviews.count } do
      post project_recertification_path(@project), params: params
    end

    assert_match(/updated their feedback/, flash[:alert])
  end

  test "a software project's dashed feedback does not gate resubmission" do
    software = Project.create!(title: "Returned software")
    software.memberships.create!(user: @owner, role: :owner)
    software.update!(ship_status: "needs_changes")
    review = software.ship_reviews.create!(status: :pending)
    review.update!(reviewer: reviewer, status: :returned, feedback: "nearly there\n- rework the CSS")

    assert_difference -> { software.ship_reviews.count }, 1 do
      post project_recertification_path(software)
    end

    assert_equal "submitted", software.reload.ship_status
  end

  test "a reviewer acting on the builder's behalf is not gated" do
    returned_review(feedback: "nearly there\n- photograph the solder joints")
    certifier = create_user(slack_id: "U_REC_CERT", display_name: "rec-cert")
    certifier.grant_role!(:project_certifier)
    sign_in certifier

    assert_difference -> { @project.ship_reviews.count }, 1 do
      post project_recertification_path(@project)
    end

    assert_equal "submitted", @project.reload.ship_status
  end

  private

  def reviewer
    @reviewer ||= begin
      user = create_user(slack_id: "U_REC_REV", display_name: "rec-rev")
      user.grant_role!(:admin)
      user
    end
  end

  def returned_review(feedback:)
    review = @project.ship_reviews.create!(status: :pending)
    review.update!(reviewer: reviewer, status: :returned, feedback: feedback)
    review
  end

  def acknowledging(review, indices:)
    {
      acknowledged_action_items: indices.map(&:to_s),
      action_items_digest: review.action_items_digest
    }
  end
end
