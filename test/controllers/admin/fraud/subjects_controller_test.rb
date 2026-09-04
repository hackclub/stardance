require "test_helper"

class Admin::Fraud::SubjectsControllerTest < ActionDispatch::IntegrationTest
  include UserFactory

  setup do
    @squad = create_user(slack_id: "U_FRAUD_SQUAD", display_name: "squaddie")
    @squad.grant_role!(:fraud_squad)

    @subject = create_user(slack_id: "U_FRAUD_SUBJECT", display_name: "subject")
    @reporter = create_user(slack_id: "U_FRAUD_REPORTER", display_name: "reporter")
    @project = Project.create!(title: "Flagged build")
    Project::Membership.create!(project: @project, user: @subject, role: :owner)
  end

  test "the queue lists someone with a fraud flag waiting" do
    flag_the_project

    sign_in @squad
    get admin_fraud_subjects_path

    assert_response :success
    assert_select "a[href=?]", admin_fraud_subject_path(@subject)
  end

  test "the queue leaves out quality reports the fraud team does not own" do
    flag_the_project(reason: "low_effort")

    sign_in @squad
    get admin_fraud_subjects_path

    assert_response :success
    assert_select "a[href=?]", admin_fraud_subject_path(@subject), count: 0
  end

  test "the subject page shows the person's waiting flags" do
    flag_the_project

    sign_in @squad
    get admin_fraud_subject_path(@subject)

    assert_response :success
    assert_select ".fraud-subject__item--flag", count: 1
  end

  test "the subject page says so when there is no Hackatime identity to look up" do
    flag_the_project

    sign_in @squad
    get admin_fraud_subject_path(@subject)

    assert_response :success
    assert_match "No Hackatime identity", response.body
  end

  test "the dashboard count badge reports how many people are waiting" do
    flag_the_project

    sign_in @squad
    get admin_dashboard_count_path("fraud_subjects")

    assert_response :success
    assert_match "1", response.body
  end

  test "a helper cannot reach the queue" do
    helper = create_user(slack_id: "U_FRAUD_HELPER", display_name: "helper")
    helper.grant_role!(:helper)

    sign_in helper
    get admin_fraud_subjects_path

    assert_response :forbidden
  end

  private

  def flag_the_project(reason: "fraud")
    Project::Report.create!(project: @project, reporter: @reporter, reason: reason,
                            details: "Detailed enough to pass validation", status: :pending)
  end
end
