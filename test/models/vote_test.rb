# == Schema Information
#
# Table name: votes
#
#  id                            :bigint           not null, primary key
#  auto_discard_checked_at       :datetime
#  demo_opened                   :boolean          default(FALSE), not null
#  discarded                     :boolean          default(FALSE), not null
#  originality_score             :integer
#  reason                        :text
#  repo_opened                   :boolean          default(FALSE), not null
#  storytelling_score            :integer
#  technical_score               :integer
#  time_taken_to_vote_in_seconds :integer
#  usability_score               :integer
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  project_id                    :bigint           not null
#  ship_event_id                 :bigint           not null
#  user_id                       :bigint           not null
#
# Indexes
#
#  index_votes_on_discarded_and_ship_event_id  (discarded,ship_event_id)
#  index_votes_on_project_id                   (project_id)
#  index_votes_on_ship_event_id                (ship_event_id)
#  index_votes_on_user_id                      (user_id)
#  index_votes_on_user_id_and_ship_event_id    (user_id,ship_event_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (project_id => projects.id)
#  fk_rails_...  (ship_event_id => post_ship_events.id)
#  fk_rails_...  (user_id => users.id)
#
require "test_helper"

class VoteTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    Flipper.enable(:ship_event_payouts)
  end

  teardown do
    Flipper.disable(:ship_event_payouts)
  end

  test "creating a vote queues payout refresh" do
    owner = create_user(slack_id: "U#{SecureRandom.hex(8)}", display_name: "owner#{SecureRandom.hex(4)}")
    voter = create_user(slack_id: "U#{SecureRandom.hex(8)}", display_name: "voter#{SecureRandom.hex(4)}")
    project = Project.create!(title: "Project #{SecureRandom.hex(4)}")
    Project::Membership.create!(project: project, user: owner, role: :owner)
    ship_event = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true, certification_status: "approved", hours_at_ship: 1)
    Post.create!(project: project, user: owner, postable: ship_event)

    assert_enqueued_with(job: ShipEventPayoutRefreshJob) do
      Vote.create!(
        user: voter,
        project: project,
        ship_event: ship_event,
        reason: "Strong implementation details with clear progress and thoughtful trade offs.",
        originality_score: 6,
        technical_score: 6,
        usability_score: 6,
        storytelling_score: 6
      )
    end
  end

  test "owner can flag a vote during payout review" do
    owner, vote = create_reviewable_vote

    assert_difference -> { Vote::Event.pending_vote_flags.count }, 1 do
      assert vote.flag_for_review_by(owner)
    end

    assert vote.pending_flag?
    assert_not vote.ship_event.votes.where.not(id: vote.id).first.pending_flag?
  end

  test "accepted flag discards vote and sends project back to voting" do
    owner, vote = create_reviewable_vote
    reviewer = create_user(slack_id: "U#{SecureRandom.hex(8)}", display_name: "reviewer#{SecureRandom.hex(4)}")
    vote.flag_for_review_by(owner)

    assert_difference -> { Vote.payout_countable.count }, -1 do
      assert vote.accept_flag(reviewer: reviewer)
    end

    assert vote.discarded?
    assert_nil vote.ship_event.reload.payout_basis_locked_at
    assert_includes Post::ShipEvent.voteable, vote.ship_event
  end

  test "rejected flag charges owner and releases payout" do
    owner, vote = create_reviewable_vote
    reviewer = create_user(slack_id: "U#{SecureRandom.hex(8)}", display_name: "reviewer#{SecureRandom.hex(4)}")
    vote.flag_for_review_by(owner)

    assert_difference -> { owner.ledger_entries.where(created_by: "vote_flag_review").sum(:amount) }, -Vote::FLAG_COST do
      assert vote.reject_flag(reviewer: reviewer)
    end

    assert_not vote.reload.discarded
    assert vote.ship_event.reload.payout.positive?
  end

  private
    def create_reviewable_vote
      owner = create_user(slack_id: "U#{SecureRandom.hex(8)}", display_name: "owner#{SecureRandom.hex(4)}")
      project = Project.create!(title: "Project #{SecureRandom.hex(4)}")
      Project::Membership.create!(project: project, user: owner, role: :owner)
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
          storytelling_score: 6
        )
      end

      ship_event.refresh_payout_score!
      ship_event.issue_payout!

      [ owner, votes.first ]
    end
end
