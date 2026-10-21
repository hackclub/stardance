require "test_helper"

# The GOI queue leaves hardware out under either flag: hardware_stage, or the
# legacy "Hardware" project type that predates it.
class Certification::YswsSoftwareOnlyTest < ActiveSupport::TestCase
  include UserFactory

  setup { @user = create_user(slack_id: "u-ysws-sw", display_name: "ysws_sw_shipper") }

  test "untyped and software-typed projects are in the queue" do
    untyped = review_on(project)
    typed = review_on(project(project_type: "Web App"))

    assert_includes Certification::Ysws.software_only, untyped
    assert_includes Certification::Ysws.software_only, typed
  end

  test "a project with a hardware stage is left out" do
    review = review_on(project(hardware_stage: "build"))

    assert_not_includes Certification::Ysws.software_only, review
  end

  test "a legacy Hardware-typed project is left out" do
    review = review_on(project(project_type: "Hardware"))

    assert_not_includes Certification::Ysws.software_only, review
  end

  private

  def project(**attrs)
    project = Project.create!(title: "YSWS SW #{SecureRandom.hex(4)}")
    Project::Membership.create!(project: project, user: @user, role: :owner)
    project.update!(attrs) if attrs.any?
    project
  end

  def review_on(project)
    ship_event = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true)
    Post.create!(project: project, user: @user, postable: ship_event)
    Certification::Ysws.create!(user: @user, project: project, post_ship_event: ship_event, original_minutes: 60)
  end
end
