require "test_helper"

# The follower/following lists are not paginated (UsersController#followers and
# #following load the whole relation), so a user with thousands of followers
# renders thousands of cachet avatar <img>s in one document. cachet serves
# /users/:slack_id/r with no Cache-Control, so every one of those is an origin
# request — enough of them at once trips the zone rate limit and 429s the
# viewer's whole session. Lazy loading keeps a long list to the avatars actually
# on screen, so it has to stay on.
class Users::FollowListTest < ActionView::TestCase
  def follower(id, slack_id: "U0#{id}SLACK")
    User.new(id: id, display_name: "builder#{id}", slack_id: slack_id)
  end

  test "avatars in a follow list are lazy loaded" do
    render partial: "users/follow_list",
           locals: { users: [ follower(1), follower(2) ], empty_text: "No followers yet." }

    assert_select "img.follow-list__avatar", count: 2
    assert_select "img.follow-list__avatar:not([loading=lazy])", count: 0
  end

  test "avatars point at cachet for users with a slack id" do
    render partial: "users/follow_list",
           locals: { users: [ follower(1, slack_id: "U0ABCDEF") ], empty_text: "No followers yet." }

    assert_select "img.follow-list__avatar[src=?]", "https://cachet.hackclub.com/users/U0ABCDEF/r"
  end

  test "renders the empty text when nobody follows the user" do
    render partial: "users/follow_list",
           locals: { users: [], empty_text: "No followers yet." }

    assert_select ".follow-list__empty", text: "No followers yet."
    assert_select "img.follow-list__avatar", count: 0
  end
end
