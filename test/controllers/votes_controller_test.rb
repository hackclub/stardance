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

    test "timeline like buttons read one precomputed set instead of a query per devlog" do
      ship_post = @target.post
      devlogs = 3.times.map do |i|
        devlog = Post::Devlog.new(body: "Progress #{i}", duration_seconds: 1.hour)
        devlog.uploading_attachments = true
        devlog.save!
        Post.create!(project: ship_post.project, user: ship_post.user, postable: devlog, created_at: ship_post.created_at - 1.hour)
        devlog
      end
      Like.create!(user: @voter, likeable: devlogs.first)

      assert_queries_match(/SELECT 1 AS one FROM "likes"/, count: 0) do
        get new_rate_url
      end

      assert_response :success
      assert_select ".vote-page__timeline .like-button__btn--liked", 1
      assert_select ".vote-page__timeline .like-button__btn", 3
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

    test "voter can bank votes up to the future ship credit limit" do
      @voter.update!(vote_balance: Vote::MAX_BANKED_VOTES - 1)

      get new_rate_url
      assignment = current_assignment
      assert_not_nil assignment

      post votes_path, params: {
        vote_assignment_id: assignment.id,
        vote: valid_scores.merge(reason: VotesControllerTest::VALID_REASON)
      }

      assert_redirected_to new_rate_path
      assert_equal Vote::MAX_BANKED_VOTES, @voter.reload.vote_balance
    end

    test "voter cannot exceed the future ship credit limit" do
      @voter.update!(vote_balance: Vote::MAX_BANKED_VOTES)

      assert_no_difference -> { @voter.vote_assignments.count } do
        get new_rate_url
      end

      assert_response :success
      assert_includes response.body, "banked #{Vote::MAX_BANKED_VOTES} votes"
    end

    test "submitting a vote stores readable telemetry on the vote" do
      get new_rate_url
      assignment = current_assignment
      assignment.update_columns(first_viewed_at: 75.seconds.ago, last_viewed_at: 10.seconds.ago)
      assignment.ship_event.project.update_columns(
        demo_url: "https://demo.example.com",
        repo_url: "https://github.com/acme/widget"
      )

      get demo_votes_assignment_path(assignment)
      get repo_votes_assignment_path(assignment)

      assert_difference -> { Vote.count }, 1 do
        post votes_path, params: {
          vote_assignment_id: assignment.id,
          vote: valid_scores.merge(reason: VotesControllerTest::VALID_REASON)
        }
      end

      vote = Vote.order(:created_at).last
      assert_operator vote.time_taken_to_vote_in_seconds, :>=, 75
      assert_predicate vote, :demo_opened?
      assert_predicate vote, :repo_opened?
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

    test "timeline posts load their authors and projects without a query per post" do
      get new_rate_url
      add_timeline_devlogs(2)
      few = single_row_lookups { get new_rate_url }

      add_timeline_devlogs(3)
      many = single_row_lookups { get new_rate_url }

      assert_response :success
      assert_select ".vote-page__timeline .feed-post-card", 6 # five devlogs and the ship
      assert_equal few, many
    end

    private
      def add_timeline_devlogs(count)
        ship_post = @target.post
        count.times do |i|
          author = create_user(slack_id: "U#{SecureRandom.hex(8)}", display_name: "author#{SecureRandom.hex(5)}")
          devlog = Post::Devlog.new(body: "Progress #{i}", duration_seconds: 1.hour)
          devlog.uploading_attachments = true
          devlog.save!
          Post.create!(project: ship_post.project, user: author, postable: devlog, created_at: ship_post.created_at - 1.hour)
        end
      end

      # Counts `WHERE id = $1` lookups per table, the shape a per-post N+1 takes.
      def single_row_lookups(&block)
        counts = Hash.new(0)
        callback = lambda do |*, payload|
          table = payload[:sql][/\ASELECT .* FROM "(users|projects|posts)" WHERE "\1"\."id" = \$1/, 1]
          counts[table] += 1 if table
        end
        ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &block)
        counts
      end

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
