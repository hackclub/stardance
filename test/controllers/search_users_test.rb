require "test_helper"

# /search/users backs the bio editor's @mention autocomplete and the audit
# log's "Performed By" filter. Both need to look a user up by id — the bio
# editor to resolve an existing mention chip, the audit log so an admin can
# paste an id straight out of the table.
class SearchUsersTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user("admin", role: :admin)
    @member = create_user("member")
  end

  test "looks a single user up by id" do
    target = create_user("byid")
    create_user("other")
    sign_in @admin

    get search_users_path(format: :json), params: { id: target.id }
    assert_response :success

    assert_equal [ target.id ], json_body.map { |u| u["id"] }
  end

  test "matches a numeric query against the id as well as the name" do
    target = create_user("numeric")
    sign_in @admin

    get search_users_path(format: :json), params: { q: target.id.to_s }

    assert_includes json_body.map { |u| u["id"] }, target.id
  end

  test "a leading # is stripped so a pasted id works" do
    target = create_user("hash")
    sign_in @admin

    get search_users_path(format: :json), params: { q: "##{target.id}" }

    assert_includes json_body.map { |u| u["id"] }, target.id
  end

  test "matches the start of a display name" do
    target = create_user("needle")
    sign_in @admin

    get search_users_path(format: :json), params: { q: "search_needle" }

    assert_equal [ target.id ], json_body.map { |u| u["id"] }
  end

  test "caps results at MAX_RESULTS" do
    12.times { |i| create_user("bulk#{i}") }
    sign_in @admin

    get search_users_path(format: :json), params: { q: "search_bulk" }

    assert_equal SearchController::MAX_RESULTS, json_body.size
  end

  test "returns a cachet avatar url for users with a slack id" do
    target = create_user("avatar")
    sign_in @admin

    get search_users_path(format: :json), params: { id: target.id }

    assert_equal "https://cachet.hackclub.com/users/#{target.slack_id}/r",
                 json_body.first["avatar"]
  end

  # `discoverable` excludes banned users, so before this the audit log filter
  # could not name a banned actor even though the log is full of their edits.
  test "admins can find a banned user" do
    banned = create_user("banned")
    banned.update!(banned: true)
    sign_in @admin

    get search_users_path(format: :json), params: { id: banned.id }

    assert_equal [ banned.id ], json_body.map { |u| u["id"] }
  end

  test "non-admins still find an ordinary user by id" do
    target = create_user("visible")
    sign_in @member

    get search_users_path(format: :json), params: { id: target.id }

    assert_equal [ target.id ], json_body.map { |u| u["id"] }
  end

  test "non-admins cannot find a banned user by id" do
    banned = create_user("hidden")
    banned.update!(banned: true)
    sign_in @member

    get search_users_path(format: :json), params: { id: banned.id }

    assert_empty json_body
  end

  test "requires a signed-in user" do
    get search_users_path(format: :json), params: { q: "search" }

    assert_response :unauthorized
  end

  private

  def json_body
    JSON.parse(response.body)
  end

  # A hack_club identity is what makes a user `discoverable`, which is the
  # scope non-admins are limited to.
  def create_user(label, role: nil)
    user = User.create!(
      slack_id: "U_SEARCH_#{label.upcase}",
      display_name: "search_#{label}",
      email: "search_#{label}@example.test",
      verification_status: "verified"
    )
    user.identities.create!(provider: "hack_club", uid: "hc_#{label}", access_token: "token_#{label}")
    user.grant_role!(role) if role
    user
  end
end
