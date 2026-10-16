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

  test "an admin impersonating a member can load their devlog preview time" do
    User::HackatimeProject.create!(user: @owner, project: @project, name: "devlog-preview")
    admin = User.create!(slack_id: "U_DEVLOG_ADMIN", display_name: "devlog_admin", email: "devlog_admin@example.test")
    admin.grant_role!(:admin)
    sign_in admin
    post admin_user_impersonation_path(@owner)

    HackatimeService.stub(:fetch_total_seconds_for_projects, 20.minutes.to_i) do
      get preview_time_project_devlogs_path(@project)
    end

    assert_response :success
    assert_includes response.body, "20m will be logged"
  end

  test "a non-member cannot load another project's devlog preview time" do
    stranger = User.create!(slack_id: "U_DEVLOG_STRANGER", display_name: "devlog_stranger", email: "devlog_stranger@example.test")
    sign_in stranger

    get preview_time_project_devlogs_path(@project)

    assert_response :forbidden
  end

  test "replacing an attachment with a file that is too large keeps the original" do
    devlog = create_devlog
    original = devlog.attachments.first
    sign_in @owner

    patch project_devlog_path(@project, devlog), params: {
      post_devlog: { body: devlog.body, attachments: [ oversized_upload ] },
      remove_attachment_ids: [ original.id ]
    }

    assert_response :unprocessable_entity
    assert_match "too large", flash[:alert]
    assert_equal [ original.id ], devlog.reload.attachments.map(&:id)
  end

  test "a devlog without attachments can add one from the edit page and still be deleted" do
    devlog = create_devlog
    devlog.attachments.each(&:purge)
    sign_in @owner

    get edit_project_devlog_path(@project, devlog)
    assert_response :success
    assert_select ".devlog-edit__attachment-replace-label", "Add a screenshot or video"

    delete project_devlog_path(@project, devlog)

    assert_redirected_to project_path(@project)
    assert Post::Devlog.unscoped.find(devlog.id).deleted?
  end

  test "the edit page offers an add slot until the devlog is at the attachment limit" do
    devlog = create_devlog
    sign_in @owner

    get edit_project_devlog_path(@project, devlog)
    assert_select ".devlog-edit__attachment-grid > .devlog-edit__attachment", 2
    assert_select ".devlog-edit__attachment-grid .devlog-edit__attachment-replace-label", text: "Add a screenshot or video", count: 1

    devlog.attachments.attach(Array.new(Post::Devlog::MAX_ATTACHMENTS - 1) { png_upload })

    get edit_project_devlog_path(@project, devlog)
    assert_select ".devlog-edit__attachment-grid > .devlog-edit__attachment", Post::Devlog::MAX_ATTACHMENTS
    assert_select ".devlog-edit__attachment-grid .devlog-edit__attachment-replace-label", text: "Add a screenshot or video", count: 0
  end

  test "adding an attachment while editing keeps the existing one" do
    devlog = create_devlog
    original = devlog.attachments.first
    sign_in @owner

    patch project_devlog_path(@project, devlog), params: {
      post_devlog: { body: devlog.body, attachments: [ png_upload ] }
    }

    assert_redirected_to project_path(@project)
    attachment_ids = devlog.reload.attachments.map(&:id)
    assert_equal 2, attachment_ids.size
    assert_includes attachment_ids, original.id
  end

  test "adding attachments past the limit is rejected without losing any" do
    devlog = create_devlog
    original = devlog.attachments.first
    sign_in @owner

    patch project_devlog_path(@project, devlog), params: {
      post_devlog: { body: "Edited body.", attachments: Array.new(Post::Devlog::MAX_ATTACHMENTS) { png_upload } }
    }

    assert_response :unprocessable_entity
    assert_match "can't have more than #{Post::Devlog::MAX_ATTACHMENTS} attachments", flash[:alert]
    devlog.reload
    assert_equal [ original.id ], devlog.attachments.map(&:id)
    assert_equal "Built the thing.", devlog.body
  end

  test "posting a devlog snapshots hackatime names as an array so commas survive" do
    User::HackatimeProject.create!(user: @owner, project: @project, name: "my,project")
    sign_in @owner
    keys_seen = []
    fake_total = ->(_uid, keys, **) { keys_seen << keys; 20.minutes.to_i }

    HackatimeService.stub(:fetch_total_seconds_for_projects, fake_total) do
      post project_devlogs_path(@project), params: {
        post_devlog: { body: "Worked on the comma project.", attachments: [ png_upload ] }
      }
    end

    assert_redirected_to project_path(@project)
    devlog = @project.devlogs.last
    assert_equal [ [ "my,project" ] ], keys_seen.uniq
    assert_equal [ "my,project" ], devlog.hackatime_project_names_snapshot
    assert_equal 20.minutes.to_i, devlog.duration_seconds
  end

  private

  def create_devlog
    devlog = Post::Devlog.new(body: "Built the thing.", duration_seconds: 1.hour)
    devlog.attachments.attach(png_upload)
    devlog.save!
    Post.create!(project: @project, user: @owner, postable: devlog)
    devlog
  end

  # Sparse file just over the 50 MB attachment limit.
  def oversized_upload
    file = Tempfile.new([ "huge", ".png" ])
    file.binmode
    file.write(File.binread(png_upload.path))
    file.truncate(Post::Devlog::ATTACHMENT_MAX_SIZE + 1)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "image/png")
  end

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
