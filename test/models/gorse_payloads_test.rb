require "test_helper"
require "base64"

class GorsePayloadsTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(
      interests: %w[web_dev hardware],
      experience_level: "some",
      regions: %w[US],
      shop_region: "US",
      verification_status: "verified",
      ysws_eligible: true
    )

    @project = projects(:one)
    @project.update!(
      title: "Orbital Notebook",
      description: "A useful project log",
      project_type: "Web App",
      devlogs_count: 1
    )

    @devlog = create_devlog(body: "Shipped a cleaner recommendation prototype today.")
    @post = Post.create!(project: @project, user: @user, postable: @devlog)
  end

  test "user payload includes stable id and onboarding labels" do
    payload = Gorse::UserPayload.new(@user).to_h

    assert_equal "user:#{@user.id}", payload[:UserId]
    assert_includes payload[:Labels][:interests], "web_dev"
    assert_equal "some", payload[:Labels][:experience_level]
    assert_equal "verified", payload[:Labels][:verification_status]
  end

  test "post payload includes feed category and project labels" do
    payload = Gorse::PostPayload.new(@post).to_h

    assert_equal "post:#{@post.id}", payload[:ItemId]
    assert_includes payload[:Categories], "feed"
    assert_equal "devlog", payload[:Labels][:type]
    assert_equal "Web App", payload[:Labels][:project_type]
    assert_equal false, payload[:IsHidden]
  end

  test "project payload hides placeholder low information projects" do
    @project.update!(title: "Untitled project", description: "", devlogs_count: 0, duration_seconds: 0, shipped_at: nil)

    assert Gorse::ProjectPayload.new(@project).hidden?
  end

  test "feedback payload maps users and items" do
    payload = Gorse::FeedbackPayload.new(user: @user, item: @post, feedback_type: :read).to_h

    assert_equal "read", payload[:FeedbackType]
    assert_equal "user:#{@user.id}", payload[:UserId]
    assert_equal "post:#{@post.id}", payload[:ItemId]
  end

  private
    def create_devlog(body:)
      devlog = Post::Devlog.new(body: body, duration_seconds: 1.hour)
      devlog.attachments.attach(
        io: StringIO.new(Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")),
        filename: "progress.png",
        content_type: "image/png"
      )
      devlog.save!
      devlog
    end
end
