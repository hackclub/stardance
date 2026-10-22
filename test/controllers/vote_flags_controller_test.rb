require "test_helper"

class VoteFlagsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Flipper.enable(:ship_event_payouts)
  end

  teardown do
    Flipper.disable(:ship_event_payouts)
  end

  test "owner flags several reasons at once, each with its own explanation" do
    owner, vote = create_reviewable_vote
    ship_event = vote.ship_event
    project = ship_event.project
    flaggable = ship_event.votes.select { |candidate| candidate.flaggable_by?(owner) }.first(2)
    sign_in owner

    assert_difference -> { Vote::Event.pending_vote_flags.count }, 2 do
      post ship_event_vote_flags_path(ship_event), params: {
        flags: flaggable.to_h do |candidate|
          [ candidate.id, { selected: "1", details: "This rating ignored the demo entirely." } ]
        end
      }
    end
    assert_redirected_to project_path(project, anchor: "payout-review")
    assert_equal "Flagged 2 ratings for review.", flash[:notice]
    assert_equal "This rating ignored the demo entirely.", flaggable.first.pending_flag.properties["details"]
  end

  test "flagging is refused when a reason is missing or too short and nothing is flagged" do
    owner, vote = create_reviewable_vote
    sign_in owner

    assert_no_difference -> { Vote::Event.pending_vote_flags.count } do
      post ship_event_vote_flags_path(vote.ship_event), params: {
        flags: { vote.id => { selected: "1", details: "too short" } }
      }
    end
    assert_redirected_to project_path(vote.ship_event.project, anchor: "payout-review")
    assert_equal "Each flagged rating needs a reason of #{Vote::FLAG_DETAILS_MIN_LENGTH} to #{Vote::FLAG_DETAILS_MAX_LENGTH} characters.", flash[:alert]
  end

  test "one rating that can no longer be flagged rolls back the whole batch" do
    owner, vote = create_reviewable_vote
    ship_event = vote.ship_event
    already_flagged, *others = ship_event.votes.select { |candidate| candidate.flaggable_by?(owner) }
    already_flagged.flag_for_review_by(owner, details: "Already flagged earlier on.")
    sign_in owner

    assert_no_difference -> { Vote::Event.pending_vote_flags.count } do
      post ship_event_vote_flags_path(ship_event), params: {
        flags: [ others.first, already_flagged ].to_h do |candidate|
          [ candidate.id, { selected: "1", details: "This rating ignored the demo entirely." } ]
        end
      }
    end
  end

  test "flagging is hidden while payout flag is off" do
    owner, vote = create_reviewable_vote
    Flipper.disable(:ship_event_payouts)
    sign_in owner

    assert_no_difference -> { Vote::Event.pending_vote_flags.count } do
      post ship_event_vote_flags_path(vote.ship_event), params: {
        flags: { vote.id => { selected: "1", details: "This rating ignored the demo entirely." } }
      }
    end
    assert_response :not_found
  end

  test "admin can review vote flags" do
    owner, vote = create_reviewable_vote
    vote.flag_for_review_by(owner, details: "This rating ignored the demo entirely.")
    admin = create_user(slack_id: "U#{SecureRandom.hex(8)}", display_name: "admin#{SecureRandom.hex(4)}")
    admin.grant_role!(:admin)
    sign_in admin

    get admin_vote_flags_path
    assert_response :success
    assert_includes response.body, "Strong implementation details"
    assert_includes response.body, "This rating ignored the demo entirely."

    assert_difference -> { Vote.payout_countable.count }, -1 do
      post admin_vote_flag_approval_path(vote.pending_flag)
    end
    assert_redirected_to admin_vote_flags_path
  end

  private
    def create_reviewable_vote
      owner = create_user(slack_id: "U#{SecureRandom.hex(8)}", display_name: "owner#{SecureRandom.hex(4)}")
      project = Project.create!(title: "Project #{SecureRandom.hex(4)}", demo_url: "https://example.com/demo", repo_url: "https://github.com/example/project")
      Project::Membership.create!(project: project, user: owner, role: :owner)
      devlog =Post::Devlog.new(body: "Built the first prototype", duration_seconds: 2.hours.to_i)
      devlog.uploading_attachments = true
      devlog.save!
      Post.create!(project: project, user: owner, postable: devlog)
      ship_event = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true, certification_status: "approved", hours_at_ship: 2)
      Post.create!(project: project, user: owner, postable: ship_event)
      ship_event.update!(hours_at_ship: 2)

      votes = Array.new(Post::ShipEvent::VOTES_REQUIRED_FOR_PAYOUT) do |index|
        voter = create_user(slack_id: "U#{SecureRandom.hex(8)}", display_name: "voter#{SecureRandom.hex(4)}#{index}")
        Vote.create!(
          user: voter,
          project: project,
          ship_event: ship_event,
          reason: "Strong implementation details with clear progress and thoughtful trade offs.",
          originality_score: 6,
          technical_score: 6,
          usability_score: 6,
          storytelling_score: 6,
          auto_discard_checked_at: Time.current
        )
      end

      ship_event.refresh_payout_score!
      ship_event.issue_payout!

      [ owner, votes.first ]
    end
end
