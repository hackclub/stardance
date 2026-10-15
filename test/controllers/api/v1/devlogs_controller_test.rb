require "test_helper"
require "base64"

class Api::V1::DevlogsControllerTest < ActionDispatch::IntegrationTest
  API_FLAG = :"public_api_2026-08-28"

  setup do
    @user = User.create!(slack_id: "U_API_DEVLOGS", display_name: "api_reader", email: "api_reader@example.test", verification_status: "verified")
    @user.regenerate_api_key
    Flipper.enable(API_FLAG, @user)

    @project = Project.create!(title: "Nebula Drift", description: "A space sim")
    @devlog = create_devlog(body: "Wired up the starfield shader", project: @project)
  end

  teardown do
    Flipper.disable(API_FLAG, @user)
  end

  test "index requires an api key" do
    get api_v1_devlogs_path

    assert_response :unauthorized
    assert_equal "Missing Authorization header", response.parsed_body["error"]
  end

  test "index rejects an unknown api key" do
    get api_v1_devlogs_path, headers: { "Authorization" => "Bearer sd_sk_nope" }

    assert_response :unauthorized
    assert_equal "Invalid API key", response.parsed_body["error"]
  end

  test "index is forbidden when the api flag is off for the user" do
    Flipper.disable(API_FLAG, @user)

    get api_v1_devlogs_path, headers: auth_headers

    assert_response :forbidden
  end

  test "index returns devlogs with media, comments and pagination" do
    commenter = User.create!(slack_id: "U_API_COMMENTER", display_name: "commenter", email: "commenter@example.test", verification_status: "verified")
    @devlog.comments.create!(user: commenter, body: "Looks great")

    get api_v1_devlogs_path, headers: auth_headers

    assert_response :success
    body = response.parsed_body
    assert_equal [ @devlog.id ], body["devlogs"].map { |d| d["id"] }

    devlog = body["devlogs"].first
    assert_equal "Wired up the starfield shader", devlog["body"]
    assert_equal 3600, devlog["duration_seconds"]
    assert_equal 0, devlog["likes_count"]
    assert_equal 1, devlog["comments_count"]

    assert_equal 1, devlog["media"].size
    assert_equal "image/png", devlog["media"].first["content_type"]
    assert devlog["media"].first["url"].present?

    comment = devlog["comments"].sole
    assert_equal "Looks great", comment["body"]
    assert_equal commenter.id, comment["author"]["id"]
    assert_equal "commenter", comment["author"]["display_name"]
    assert comment["author"]["avatar"].present?

    assert_equal({ "current_page" => 1, "total_pages" => 1, "total_count" => 1, "next_page" => nil }, body["pagination"])
  end

  test "index omits comments from banned authors" do
    banned = User.create!(slack_id: "U_API_BANNED", display_name: "banned_one", email: "banned@example.test", verification_status: "verified", banned: true)
    @devlog.comments.create!(user: banned, body: "spam")

    get api_v1_devlogs_path, headers: auth_headers

    assert_response :success
    assert_empty response.parsed_body["devlogs"].sole["comments"]
  end

  test "index omits devlogs from unverified authors and soft-deleted devlogs" do
    unverified = User.create!(slack_id: "U_API_UNVERIFIED", display_name: "unverified_one", email: "unverified@example.test", verification_status: "pending")
    create_devlog(body: "Hidden log", project: @project, user: unverified)
    create_devlog(body: "Deleted log", project: @project).soft_delete!

    get api_v1_devlogs_path, headers: auth_headers

    assert_response :success
    assert_equal [ @devlog.id ], response.parsed_body["devlogs"].map { |d| d["id"] }
  end

  test "index omits devlogs belonging to a soft-deleted project" do
    other_project = Project.create!(title: "Doomed", description: "Going away")
    create_devlog(body: "Log on a deleted project", project: other_project)
    other_project.soft_delete!

    get api_v1_devlogs_path, headers: auth_headers

    assert_response :success
    assert_equal [ @devlog.id ], response.parsed_body["devlogs"].map { |d| d["id"] }
  end

  test "index is newest first and honours page and limit" do
    older = create_devlog(body: "Older log", project: @project)
    older.update_columns(created_at: 2.days.ago)

    get api_v1_devlogs_path, params: { limit: 1 }, headers: auth_headers

    assert_response :success
    assert_equal [ @devlog.id ], response.parsed_body["devlogs"].map { |d| d["id"] }
    assert_equal 2, response.parsed_body["pagination"]["next_page"]

    get api_v1_devlogs_path, params: { limit: 1, page: 2 }, headers: auth_headers

    assert_response :success
    assert_equal [ older.id ], response.parsed_body["devlogs"].map { |d| d["id"] }
  end

  test "index defaults to the standard page size" do
    get api_v1_devlogs_path, headers: auth_headers

    assert_response :success
    assert_equal Api::V1::PublicApiController::PER_PAGE, @controller.view_assigns["pagy"].limit
  end

  test "index rejects a limit above the maximum page size" do
    get api_v1_devlogs_path, params: { limit: 5_000 }, headers: auth_headers

    assert_response :bad_request
    assert_equal "Limit cannot exceed 100", response.parsed_body["error"]
  end

  test "index rejects a limit that is not a positive integer" do
    [ "0", "-5", "abc", "1.5" ].each do |bad_limit|
      get api_v1_devlogs_path, params: { limit: bad_limit }, headers: auth_headers

      assert_response :bad_request, "expected limit=#{bad_limit} to be rejected"
      assert_equal "Limit must be a positive integer", response.parsed_body["error"]
    end
  end

  test "index tolerates a page beyond the last one" do
    get api_v1_devlogs_path, params: { page: 999 }, headers: auth_headers

    assert_response :success
    assert_empty response.parsed_body["devlogs"]
  end

  test "project devlogs index is scoped to that project" do
    other_project = Project.create!(title: "Comet Tail", description: "Another one")
    other_devlog = create_devlog(body: "Different project log", project: other_project)

    get api_v1_project_devlogs_path(@project), headers: auth_headers

    assert_response :success
    ids = response.parsed_body["devlogs"].map { |d| d["id"] }
    assert_equal [ @devlog.id ], ids
    assert_not_includes ids, other_devlog.id
  end

  test "project devlogs index 404s for an unknown project" do
    get api_v1_project_devlogs_path(project_id: 0), headers: auth_headers

    assert_response :not_found
    assert_equal "Resource not found", response.parsed_body["error"]
  end

  test "show returns a single devlog" do
    get api_v1_devlog_path(@devlog), headers: auth_headers

    assert_response :success
    assert_equal @devlog.id, response.parsed_body["id"]
    assert_equal "Wired up the starfield shader", response.parsed_body["body"]
  end

  test "show 404s for a devlog the caller cannot see" do
    hidden = create_devlog(body: "Hidden log", project: @project)
    hidden.soft_delete!

    get api_v1_devlog_path(hidden), headers: auth_headers

    assert_response :not_found
  end

  private
    def auth_headers
      { "Authorization" => "Bearer #{@user.api_key}" }
    end

    def create_devlog(body:, project:, user: @user)
      devlog = Post::Devlog.new(body: body, duration_seconds: 1.hour)
      devlog.attachments.attach(
        io: StringIO.new(Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")),
        filename: "progress.png",
        content_type: "image/png"
      )
      devlog.save!
      Post.create!(project: project, user: user, postable: devlog)
      devlog
    end
end
