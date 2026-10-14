require "test_helper"

class Admin::Users::Votes::DiscardsControllerTest < ActionDispatch::IntegrationTest
  include UserFactory
  include VotingFactory

  setup do
    @admin = create_user(slack_id: "U_VOTE_DISCARD_ADMIN", display_name: "vote_discard_admin")
    @admin.grant_role!(:admin)
    @voter = create_eligible_voter
    @vote = cast_vote
  end

  test "the discard control renders for an admin on a counted rating" do
    sign_in @admin

    get admin_user_votes_path(@voter)

    assert_response :success
    assert_select "form[action=?]", admin_user_vote_discard_path(@voter, @vote)
  end

  test "an admin discards a rating with a reason" do
    sign_in @admin

    post admin_user_vote_discard_path(@voter, @vote), params: { reason: "Copy pasted feedback across ten ships" }

    assert_redirected_to admin_user_votes_path(@voter)
    assert_predicate @vote.reload, :discarded?

    event = @vote.events.find_by(event_type: "vote_discarded")
    assert_equal @admin, event.user
    assert_equal "Copy pasted feedback across ten ships", event.properties["reason"]
    assert_equal false, event.properties["automated"]
  end

  test "a discarded rating shows who threw it out and stops offering the control" do
    @vote.discard_by!(reviewer: @admin, reason: "Copy pasted feedback")
    sign_in @admin

    get admin_user_votes_path(@voter)

    assert_response :success
    assert_select ".admin-vote-status__note", text: /vote_discard_admin: Copy pasted feedback/
    assert_select "form[action=?]", admin_user_vote_discard_path(@voter, @vote), count: 0
  end

  test "a reason is required" do
    sign_in @admin

    post admin_user_vote_discard_path(@voter, @vote), params: { reason: "  " }

    assert_redirected_to admin_user_votes_path(@voter)
    assert_equal "A reason is required to discard a rating.", flash[:alert]
    assert_not_predicate @vote.reload, :discarded?
  end

  test "discarding twice is reported rather than double counted" do
    @vote.discard_by!(reviewer: @admin, reason: "First call")
    sign_in @admin

    assert_no_difference -> { Vote::Event.of_type("vote_discarded").count } do
      post admin_user_vote_discard_path(@voter, @vote), params: { reason: "Second call" }
    end

    assert_equal "That rating was already discarded.", flash[:alert]
  end

  test "an nda helper reads the page but cannot discard" do
    nda_helper = create_user(slack_id: "U_VOTE_DISCARD_NDA", display_name: "vote_discard_nda")
    nda_helper.grant_role!(:nda_helper)
    sign_in nda_helper

    get admin_user_votes_path(@voter)
    assert_response :success
    assert_select "form[action=?]", admin_user_vote_discard_path(@voter, @vote), count: 0

    post admin_user_vote_discard_path(@voter, @vote), params: { reason: "Not mine to make" }
    assert_response :forbidden
    assert_not_predicate @vote.reload, :discarded?
  end

  private

  def cast_vote
    assignment = Vote::Assignment.create!(user: @voter, ship_event: create_voteable_ship_event)
    assignment.submit_vote(
      originality_score: 6,
      technical_score: 6,
      usability_score: 6,
      storytelling_score: 6,
      reason: "Strong implementation details with clear progress and thoughtful trade offs."
    )
  end
end
