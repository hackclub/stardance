require "test_helper"

class Admin::Fraud::SubjectsControllerTest < ActionDispatch::IntegrationTest
  include UserFactory
  include TelescreenHelper
  include FraudDetectionDataStub

  setup do
    @squad = create_user(slack_id: "U_FRAUD_SQUAD", display_name: "squaddie")
    @squad.grant_role!(:fraud_fraud_squad_squad)

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
    assert_select ".fraud-subject-card__avatar[src=?]", @subject.avatar
  end

  test "the queue leaves out someone another reviewer is holding" do
    flag_the_project
    holder = create_user(slack_id: "U_FRAUD_HOLDER", display_name: "holder")
    FraudSubjectClaim.claim(@subject, holder)

    sign_in @squad
    get admin_fraud_subjects_path

    assert_response :success
    assert_select "a[href=?]", admin_fraud_subject_path(@subject), count: 0
    assert_select ".fraud-queue__empty"
  end

  test "the queue still lists the person the reviewer is holding themselves" do
    flag_the_project
    FraudSubjectClaim.claim(@subject, @squad)

    sign_in @squad
    get admin_fraud_subjects_path

    assert_response :success
    assert_select "a[href=?]", admin_fraud_subject_path(@subject)
  end

  test "the progress bar gives each waiting item one slot" do
    flag_the_project
    pending_integrity_check(@project)

    sign_in @squad
    get admin_fraud_subject_path(@subject)

    assert_response :success
    assert_select ".fraud-subject__progress-slot", count: 2
    assert_select ".fraud-subject__progress-slot--flag", count: 1
    assert_select ".fraud-subject__progress-slot--integrity", count: 1
    assert_select ".fraud-subject__progress-slot--done", count: 0
  end

  test "opening a person takes them for the reviewer" do
    flag_the_project

    sign_in @squad
    get admin_fraud_subject_path(@subject)

    assert_response :success
    assert_equal @squad.id, FraudSubjectClaim.sole.reviewer_id
    assert_select ".fraud-subject__claim", count: 0
  end

  test "a person held by someone else shows the holder and hides the verdicts" do
    holder = create_user(slack_id: "U_FRAUD_HOLDS", display_name: "holdsit")
    FraudSubjectClaim.claim(@subject, holder)
    flag_the_project

    sign_in @squad
    get admin_fraud_subject_path(@subject)

    assert_response :success
    assert_select ".fraud-subject--claimed-elsewhere"
    assert_select ".fraud-subject__claim", text: /holdsit/
    assert_equal holder.id, FraudSubjectClaim.sole.reviewer_id, "the holder is not displaced"
  end

  test "a cleared person offers the next one in the queue" do
    other = create_user(slack_id: "U_FRAUD_NEXT", display_name: "nextup")
    project = Project.create!(title: "Next flagged")
    Project::Membership.create!(project:, user: other, role: :owner)
    Project::Report.create!(project:, reporter: @squad, reason: "fraud",
                            details: "Detailed fraud report body for the test suite.")

    sign_in @squad
    get admin_fraud_subject_path(@subject)

    assert_response :success
    assert_select "a.fraud-subject__next-button[href=?]", admin_fraud_subject_path(other)
  end

  test "a person still waiting on a verdict gets no next button" do
    flag_the_project

    sign_in @squad
    get admin_fraud_subject_path(@subject)

    assert_response :success
    assert_select ".fraud-subject__next-button", count: 0
  end

  test "the next person skips anyone another reviewer is holding" do
    held = create_user(slack_id: "U_FRAUD_HELD", display_name: "heldup")
    holder = create_user(slack_id: "U_FRAUD_HOLDER2", display_name: "holder2")
    project = Project.create!(title: "Held flagged")
    Project::Membership.create!(project:, user: held, role: :owner)
    Project::Report.create!(project:, reporter: @squad, reason: "fraud",
                            details: "Detailed fraud report body for the test suite.")
    FraudSubjectClaim.claim(held, holder)

    sign_in @squad
    get admin_fraud_subject_path(@subject)

    assert_response :success
    assert_select ".fraud-subject__next-button", count: 0
    assert_select ".fraud-subject__next-empty"
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

  test "the subject page identifies the person being reviewed" do
    flag_the_project

    sign_in @squad
    get admin_fraud_subject_path(@subject)

    assert_response :success
    assert_match @subject.email, response.body
    assert_match "U_FRAUD_SUBJECT", response.body
    assert_match "Needs submission", response.body
    assert_select ".fraud-subject__avatar[src=?]", @subject.avatar
  end

  test "the subject page breaks submitted projects down by payout, keys and credited time" do
    ship = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true)
    ship.update_columns(certification_status: "approved", payout: 42)
    Post.create!(project: @project, user: @subject, postable: ship)

    devlog = Post::Devlog.create!(body: "Built the thing", duration_seconds: 90.minutes.to_i,
                                  hackatime_projects_key_snapshot: "api,web", uploading_attachments: true)
    Post.create!(project: @project, user: @subject, postable: devlog)

    sign_in @squad
    get admin_fraud_subject_path(@subject)

    assert_response :success
    assert_select "#fraud-subject-projects", text: /Submitted projects/
    assert_match "42.0", response.body
    assert_match "api + web", response.body
    assert_match "1.5 hours logged", response.body
  end

  test "the subject page describes the project behind each integrity check" do
    project = Project.create!(title: "Shipped build", project_type: "Web App",
                              ship_status: "submitted", duration_seconds: 3.hours.to_i,
                              shipped_at: 2.days.ago,
                              description: "What the ship actually does",
                              repo_url: "https://github.com/example/repo",
                              demo_url: "https://example.com/demo")
    pending_integrity_check(project)

    sign_in @squad
    get admin_fraud_subject_path(@subject)

    assert_response :success
    assert_match "##{project.id}", response.body
    assert_match "Web App", response.body
    assert_match "Submitted", response.body
    assert_match "3.0 hours", response.body
    assert_match "What the ship actually does", response.body
    assert_select "a[href=?]", "https://github.com/example/repo"
    assert_select "a[href=?]", "https://example.com/demo"
  end

  test "each integrity check links its Hackatime projects into Telescreen" do
    project = Project.create!(title: "Shipped build")
    pending_integrity_check(project)
    @subject.identities.create!(provider: "hackatime", uid: "4242", access_token: "t")
    User::HackatimeProject.insert_all([
      { user_id: @subject.id, project_id: project.id, name: "orbit-os", created_at: Time.current, updated_at: Time.current },
      { user_id: @subject.id, project_id: project.id, name: "orbit os v2", created_at: Time.current, updated_at: Time.current }
    ])

    sign_in @squad
    get admin_fraud_subject_path(@subject)

    assert_response :success
    assert_select ".fraud-subject__item--integrity a[href=?]",
                  telescreen_hackatime_overview_url("4242", project: "orbit-os")
    assert_select ".fraud-subject__item--integrity a[href=?]",
                  telescreen_hackatime_overview_url("4242", project: "orbit os v2")
    assert_select ".fraud-subject__item--integrity a[href=?]",
                  telescreen_hackatime_overview_url("4242", project: [ "orbit-os", "orbit os v2" ])
  end

  test "a single Hackatime project gets no all-projects link" do
    project = Project.create!(title: "Shipped build")
    pending_integrity_check(project)
    @subject.identities.create!(provider: "hackatime", uid: "4242", access_token: "t")
    User::HackatimeProject.insert_all([
      { user_id: @subject.id, project_id: project.id, name: "orbit-os", created_at: Time.current, updated_at: Time.current }
    ])

    sign_in @squad
    get admin_fraud_subject_path(@subject)

    assert_response :success
    assert_select ".fraud-subject__tool-link--all", count: 0
  end

  test "the subject page shows the detection signals behind an integrity check" do
    pending_integrity_check(@project)

    with_detection_data("percentage_of_something" => 0.42) do
      sign_in @squad
      get admin_fraud_subject_path(@subject)
    end

    assert_response :success
    assert_match "Review reasoning", response.body
    assert_match "Percentage of something", response.body
    assert_match "42.0%", response.body
  end

  test "the subject page leaves out review reasoning when nothing was detected" do
    pending_integrity_check(@project)

    sign_in @squad
    get admin_fraud_subject_path(@subject)

    assert_response :success
    assert_no_match "Review reasoning", response.body
  end

  test "a helper cannot reach the queue" do
    helper = create_user(slack_id: "U_FRAUD_HELPER", display_name: "helper")
    helper.grant_role!(:helper)

    sign_in helper
    get admin_fraud_subjects_path

    assert_response :forbidden
  end

  private

  def pending_integrity_check(project)
    Project::Membership.create!(project: project, user: @subject, role: :owner) unless
      Project::Membership.exists?(project: project, user: @subject)
    ship_event = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true)
    Post.create!(project: project, user: @subject, postable: ship_event)
    Certification::Integrity.create!(ship_event: ship_event, status: :pending)
  end

  def flag_the_project(reason: "fraud")
    Project::Report.create!(project: @project, reporter: @reporter, reason: reason,
                            details: "Detailed enough to pass validation", status: :pending)
  end
end
