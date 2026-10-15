require "test_helper"
require "base64"

# The flat /devlogs/:devlog_id like and comment routes must respect
# Post.visible_to, same as the nested devlog page: a devlog by an author
# without ID verification is hidden from everyone but its author and admins.
class DevlogInteractionsVisibilityTest < ActionDispatch::IntegrationTest
  setup do
    @viewer = create_user(slack_id: "U_DIV_VIEWER", display_name: "div_viewer", verified: true)
    @verified_author = create_user(slack_id: "U_DIV_VER", display_name: "div_ver", verified: true)
    @unverified_author = create_user(slack_id: "U_DIV_UNV", display_name: "div_unv")

    @project = Project.create!(title: "Visibility", description: "d")
    @project.memberships.create!(user: @verified_author, role: :owner)
    @project.memberships.create!(user: @unverified_author, role: :contributor)

    @visible_devlog = create_devlog(author: @verified_author, body: "verified author devlog")
    @hidden_devlog = create_devlog(author: @unverified_author, body: "unverified author devlog")
  end

  test "liking a devlog by an unverified author is not found" do
    sign_in @viewer

    assert_no_difference -> { Like.count } do
      post devlog_like_path(@hidden_devlog), as: :turbo_stream
    end
    assert_response :not_found
  end

  test "commenting on a devlog by an unverified author is not found" do
    sign_in @viewer

    assert_no_difference -> { Comment.count } do
      post devlog_comments_path(@hidden_devlog), params: { comment: { body: "hi" } }, as: :turbo_stream
    end
    assert_response :not_found
  end

  test "a devlog by a verified author can still be liked and commented on" do
    sign_in @viewer

    assert_difference -> { @visible_devlog.likes.count }, 1 do
      post devlog_like_path(@visible_devlog), as: :turbo_stream
    end
    assert_response :success

    assert_difference -> { @visible_devlog.comments.count }, 1 do
      post devlog_comments_path(@visible_devlog), params: { comment: { body: "nice" } }, as: :turbo_stream
    end
    assert_response :success
  end

  test "an unverified author can still like their own devlog" do
    sign_in @unverified_author

    assert_difference -> { @hidden_devlog.likes.count }, 1 do
      post devlog_like_path(@hidden_devlog), as: :turbo_stream
    end
    assert_response :success
  end

  private

  def create_devlog(author:, body:)
    devlog = Post::Devlog.new(body: body, duration_seconds: 1.hour)
    devlog.attachments.attach(
      io: StringIO.new(Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")),
      filename: "progress.png",
      content_type: "image/png"
    )
    devlog.save!
    Post.create!(project: @project, user: author, postable: devlog)
    devlog
  end
end
