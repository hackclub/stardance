require "test_helper"

class My::VotesControllerTest < ActionDispatch::IntegrationTest
  include VotingFactory

  REASON = "This is a genuinely thoughtful and sufficiently detailed piece of feedback here."

  setup do
    @voter = create_eligible_voter
    sign_in @voter
  end

  test "index lists the signed-in user's ratings with scores and feedback" do
    ship_event = create_voteable_ship_event
    Vote.create!(user: @voter, ship_event: ship_event, project: ship_event.project, reason: REASON,
                 originality_score: 7, technical_score: 6, usability_score: 5, storytelling_score: 4)

    other_ship_event = create_voteable_ship_event
    Vote.create!(user: create_voting_user, ship_event: other_ship_event, project: other_ship_event.project, reason: REASON,
                 originality_score: 1, technical_score: 1, usability_score: 1, storytelling_score: 1)

    get my_ratings_path

    assert_response :success
    assert_select "a", text: ship_event.project.title
    assert_select "a", text: other_ship_event.project.title, count: 0
    assert_select "p", text: /Originality 7\/9/
    assert_select "p", text: REASON
  end

  test "index shows the empty state when the user has not rated anything" do
    get my_ratings_path

    assert_response :success
    assert_select ".notifications-page__empty:not([hidden])"
  end

  test "rate page links to past ratings" do
    Flipper.enable(:voting)
    create_voteable_ship_event

    get new_rate_path

    assert_select "a.vote-page__past-ratings[href=?]", my_ratings_path
  ensure
    Flipper.disable(:voting)
  end
end
