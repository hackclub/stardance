require "test_helper"

class Admin::Certification::ReviewNotesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Flipper.enable(:hardware_flow)

    @reviewer = create_user(slack_id: "U_RN_REV", display_name: "rn-reviewer")
    @reviewer.grant_role!(:admin)

    @owner = create_user(slack_id: "U_RN_OWNER", display_name: "rn-owner", verified: true)
    @project = hardware_project("Note bot", "design")

    sign_in @reviewer
  end

  teardown { Flipper.disable(:hardware_flow) }

  test "a reviewer can add an internal note" do
    assert_difference -> { @project.review_notes.count }, 1 do
      post admin_certification_project_review_notes_path(@project),
           params: { certification_review_note: { body: "Watch the power budget on this one." } }
    end

    note = @project.review_notes.order(:created_at).last
    assert_equal "Watch the power budget on this one.", note.body
    assert_equal @reviewer, note.author
    assert_redirected_to admin_certification_hardware_review_path(@project)
  end

  test "a blank note is not created" do
    assert_no_difference -> { @project.review_notes.count } do
      post admin_certification_project_review_notes_path(@project),
           params: { certification_review_note: { body: "" } }
    end

    assert_redirected_to admin_certification_hardware_review_path(@project)
  end

  test "a note is recorded in paper_trail with the reviewer as whodunnit" do
    post admin_certification_project_review_notes_path(@project),
         params: { certification_review_note: { body: "Auditable note." } }

    version = @project.review_notes.order(:created_at).last.versions.last
    assert_equal @reviewer.id.to_s, version.whodunnit
  end

  test "a reviewer cannot add a note to their own project" do
    @project.memberships.create!(user: @reviewer, role: :contributor)

    assert_no_difference -> { @project.review_notes.count } do
      post admin_certification_project_review_notes_path(@project),
           params: { certification_review_note: { body: "Can't note my own project." } }
    end

    assert_response :forbidden
  end

  test "a non-reviewer cannot add a note" do
    sign_in @owner

    assert_no_difference -> { @project.review_notes.count } do
      post admin_certification_project_review_notes_path(@project),
           params: { certification_review_note: { body: "Not allowed." } }
    end

    assert_response :forbidden
  end

  test "existing notes render on the review page, newest first" do
    @project.review_notes.create!(author: @reviewer, body: "First note", created_at: 2.days.ago)
    @project.review_notes.create!(author: @reviewer, body: "Second note", created_at: 1.hour.ago)

    get admin_certification_hardware_review_path(@project)

    assert_response :success
    assert_select ".reviewer-notes__item:first-child .reviewer-notes__body", text: /Second note/
    assert_select ".reviewer-notes__item:last-child .reviewer-notes__body", text: /First note/
    # The add-note form is present for a reviewer viewing the page.
    assert_select ".reviewer-notes__form textarea[name=?]", "certification_review_note[body]"
  end

  test "the panel shows an empty state when there are no notes" do
    get admin_certification_hardware_review_path(@project)

    assert_response :success
    assert_select ".reviewer-notes__empty"
    assert_select ".reviewer-notes__item", count: 0
  end

  private

  def hardware_project(title, stage)
    project = Project.create!(title: title)
    project.memberships.create!(user: @owner, role: :owner)
    project.update!(hardware_stage: stage)
    project
  end
end
