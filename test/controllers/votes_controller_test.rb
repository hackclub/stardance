require "test_helper"

class VotesControllerTest < ActionDispatch::IntegrationTest
  include VotingFactory

  VALID_REASON = "This is a genuinely thoughtful and sufficiently detailed piece of feedback here."

  test "renders the empty state without crashing when signed out" do
    get new_rate_url
    assert_response :success
  end

  class WhenVotingOpen < ActionDispatch::IntegrationTest
    include VotingFactory

    setup do
      Flipper.enable(:voting)
      @voter = create_eligible_voter
      @target = create_voteable_ship_event
      sign_in @voter
    end

    teardown do
      Flipper.disable(:voting)
    end

    test "viewing the page records assigned and viewed events and bumps the summary" do
      get new_rate_url
      assert_response :success

      assignment = current_assignment
      assert_not_nil assignment
      assert_equal 1, assignment.view_count
      assert_not_nil assignment.first_viewed_at

      assert Vote::Event.of_type("vote_assignment_assigned").where(vote_assignment: assignment).exists?
      assert Vote::Event.of_type("vote_assignment_viewed").where(vote_assignment: assignment).exists?
    end

    test "submitting a vote records attempt and submitted events" do
      get new_rate_url
      assignment = current_assignment

      assert_difference -> { Vote.count }, 1 do
        post votes_path, params: {
          vote_assignment_id: assignment.id,
          vote: valid_scores.merge(reason: VotesControllerTest::VALID_REASON)
        }
      end

      assert_redirected_to new_rate_path
      assignment.reload
      assert_not_nil assignment.submitted_at
      assert assignment.submitted?

      assert Vote::Event.of_type("vote_submit_attempted").where(vote_assignment: assignment).exists?
      submitted = Vote::Event.of_type("vote_submitted").where(vote_assignment: assignment).last
      assert_not_nil submitted
      assert_not_nil submitted.vote_id
      assert submitted.properties.key?("feedback_word_count")
      assert submitted.properties.key?("score_average")
    end

    test "skipping records a skip event and timestamp" do
      get new_rate_url
      assignment = current_assignment

      post votes_skip_path, params: { vote_assignment_id: assignment.id }

      assert_redirected_to new_rate_path
      assignment.reload
      assert assignment.skipped?
      assert_not_nil assignment.skipped_at
      assert Vote::Event.of_type("vote_skipped").where(vote_assignment: assignment).exists?
    end

    test "demo proxy records an open event and redirects to the project url" do
      get new_rate_url
      assignment = current_assignment
      assignment.ship_event.project.update_columns(demo_url: "https://demo.example.com")

      get demo_votes_assignment_path(assignment)

      assert_redirected_to "https://demo.example.com"
      assert Vote::Event.of_type("vote_demo_opened").where(vote_assignment: assignment).exists?
    end

    test "repo proxy records an open event and redirects to the project url" do
      get new_rate_url
      assignment = current_assignment
      assignment.ship_event.project.update_columns(repo_url: "https://github.com/acme/widget")

      get repo_votes_assignment_path(assignment)

      assert_redirected_to "https://github.com/acme/widget"
      assert Vote::Event.of_type("vote_repo_opened").where(vote_assignment: assignment).exists?
    end

    test "cannot open another voter's assignment links" do
      other_assignment = Vote::Assignment.create!(
        user: create_voting_user,
        ship_event: create_voteable_ship_event(demo_url: "https://secret.example.com")
      )

      get demo_votes_assignment_path(other_assignment)

      assert_response :not_found
      assert_not Vote::Event.of_type("vote_demo_opened").where(vote_assignment: other_assignment).exists?
    end

    test "cannot open repo link for a submitted assignment" do
      get new_rate_url
      assignment = current_assignment
      assignment.ship_event.project.update_columns(repo_url: "https://github.com/acme/widget")
      assignment.update!(status: :submitted, submitted_at: Time.current)

      get repo_votes_assignment_path(assignment)

      assert_response :not_found
      assert_not Vote::Event.of_type("vote_repo_opened").where(vote_assignment: assignment).exists?
    end

    test "cannot open demo link for a skipped assignment" do
      get new_rate_url
      assignment = current_assignment
      assignment.ship_event.project.update_columns(demo_url: "https://demo.example.com")
      assignment.update!(status: :skipped, skipped_at: Time.current)

      get demo_votes_assignment_path(assignment)

      assert_response :not_found
      assert_not Vote::Event.of_type("vote_demo_opened").where(vote_assignment: assignment).exists?
    end

    test "cannot open repo link for an expired assignment" do
      get new_rate_url
      assignment = current_assignment
      assignment.ship_event.project.update_columns(repo_url: "https://github.com/acme/old")
      assignment.update!(status: :expired)

      get repo_votes_assignment_path(assignment)

      assert_response :not_found
      assert_not Vote::Event.of_type("vote_repo_opened").where(vote_assignment: assignment).exists?
    end

    private
      def current_assignment
        @voter.vote_assignments.where(status: %w[assigned submitted skipped]).order(:created_at).last
      end

      def valid_scores
        {
          originality_score: 5,
          technical_score: 6,
          usability_score: 7,
          storytelling_score: 8
        }
      end
  end
end
