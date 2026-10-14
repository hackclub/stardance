require "test_helper"
require "base64"
require "tempfile"

class Projects::DevlogsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Flipper.enable(:hardware_flow)
    @owner = User.create!(slack_id: "U_DEVLOG_OWNER", display_name: "devlog_owner", email: "devlog_owner@example.test")
    @project = Project.create!(title: "No Hackatime Yet", description: "Still needs setup")
    @project.memberships.create!(user: @owner, role: :owner)
  end

  test "posting a devlog without linked hackatime project returns to project page" do
    sign_in @owner

    post project_devlogs_path(@project), params: {
      post_devlog: {
        body: "Worked on the first pass."
      }
    }

    assert_redirected_to project_path(@project)
    assert_equal "You must link at least one Hackatime project before posting a devlog", flash[:alert]
  end

  test "hardware projects still require a linked hackatime project to post a devlog" do
    @project.update!(hardware_stage: "build")
    sign_in @owner

    post project_devlogs_path(@project), params: {
      post_devlog: { body: "Soldered the first board." }
    }

    assert_redirected_to project_path(@project)
    assert_equal "You must link at least one Hackatime project before posting a devlog", flash[:alert]
  end

  private

  # A real 1x1 PNG so ActiveStorage's spoofing protection accepts it.
  def png_upload
    data = Base64.decode64(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    )
    file = Tempfile.new([ "devlog", ".png" ])
    file.binmode
    file.write(data)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "image/png")
  end
end
