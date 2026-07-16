require "test_helper"

class LikesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @author = User.create!(slack_id: "U_LIKE_AUTHOR", display_name: "likeauthor", email: "likeauthor@example.test")
    @author.identities.create!(provider: "hack_club", uid: "hca_like_author", access_token: "fake-token-like-author")
    @liker = User.create!(slack_id: "U_LIKE_LIKER", display_name: "likeliker", email: "likeliker@example.test")
    @liker.identities.create!(provider: "hack_club", uid: "hca_like_liker", access_token: "fake-token-like-liker")

    @project = Project.create!(title: "Likeable Project", description: "A project with a likeable devlog")
    @project.memberships.create!(user: @author, role: :owner)

    @devlog = Post::Devlog.new(body: "work log", duration_seconds: 1.hour)
    @devlog.uploading_attachments = true
    @devlog.save!
    Post.create!(project: @project, user: @author, postable: @devlog)
  end

  test "create responds with authoritative json state and persists the like" do
    sign_in @liker

    assert_difference -> { @devlog.likes.count }, 1 do
      post devlog_like_path(@devlog), as: :json
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["liked"]
    assert_equal 1, body["count"]
  end

  test "destroy responds with json state and removes the like" do
    sign_in @liker
    @devlog.likes.create!(user: @liker)

    assert_difference -> { @devlog.likes.count }, -1 do
      delete devlog_like_path(@devlog), as: :json
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal false, body["liked"]
    assert_equal 0, body["count"]
  end

  test "create still serves a turbo_stream that replaces the like button" do
    sign_in @liker

    post devlog_like_path(@devlog), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match "turbo-stream", response.media_type
    assert_match "like-button__btn", response.body
  end

  test "guests cannot create a like" do
    assert_no_difference -> { Like.count } do
      post devlog_like_path(@devlog), as: :json
    end
  end
end
