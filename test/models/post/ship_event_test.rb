# == Schema Information
#
# Table name: post_ship_events
#
#  id                         :bigint           not null, primary key
#  body                       :string
#  certification_status       :string           default("pending")
#  feedback_reason            :text
#  feedback_video_url         :string
#  hours_at_payout            :float
#  hours_at_ship              :float
#  multiplier                 :float
#  originality_median         :decimal(5, 2)
#  originality_percentile     :decimal(5, 2)
#  overall_percentile         :decimal(5, 2)
#  overall_score              :decimal(5, 2)
#  payout                     :float
#  payout_basis_locked_at     :datetime
#  payout_basis_overall_score :decimal(5, 2)
#  payout_basis_percentile    :decimal(5, 2)
#  payout_basis_vote_ids      :bigint           default([]), not null, is an Array
#  payout_blessing            :string
#  payout_curve_version       :string
#  review_instructions        :text
#  storytelling_median        :decimal(5, 2)
#  storytelling_percentile    :decimal(5, 2)
#  synced_at                  :datetime
#  technical_median           :decimal(5, 2)
#  technical_percentile       :decimal(5, 2)
#  usability_median           :decimal(5, 2)
#  usability_percentile       :decimal(5, 2)
#  votes_count                :integer          default(0), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#
require "test_helper"

class Post::ShipEventTest < ActiveSupport::TestCase
  setup do
    Flipper.enable(:ship_event_payouts)
    @owner = create_user(slack_id: "U#{SecureRandom.hex(8)}", display_name: "owner#{SecureRandom.hex(4)}")
  end

  teardown do
    Flipper.disable(:ship_event_payouts)
  end

  test "review_instructions allows nil" do
    ship_event = Post::ShipEvent.new(body: "test", review_instructions: nil, uploading_attachments: true)
    ship_event.valid?
    assert_empty ship_event.errors[:review_instructions]
  end

  test "review_instructions allows blank" do
    ship_event = Post::ShipEvent.new(body: "test", review_instructions: "", uploading_attachments: true)
    ship_event.valid?
    assert_empty ship_event.errors[:review_instructions]
  end

  test "review_instructions allows up to 2000 characters" do
    ship_event = Post::ShipEvent.new(body: "test", review_instructions: "x" * 2000, uploading_attachments: true)
    ship_event.valid?
    assert_empty ship_event.errors[:review_instructions]
  end

  test "review_instructions rejects over 2000 characters" do
    ship_event = Post::ShipEvent.new(body: "test", review_instructions: "x" * 2001, uploading_attachments: true)
    ship_event.valid?
    assert_not_empty ship_event.errors[:review_instructions]
  end

  test "refresh_payout_score! stores medians and percentiles" do
    low_ship = create_ship_event(hours: 2, scores: [ 2, 2, 2, 2 ])
    high_ship = create_ship_event(hours: 2, scores: [ 8, 8, 8, 8 ])

    high_ship.refresh_payout_score!

    high_ship.reload
    assert_equal 8, high_ship.originality_median.to_f
    assert_equal 8, high_ship.technical_median.to_f
    assert_equal 8, high_ship.usability_median.to_f
    assert_equal 8, high_ship.storytelling_median.to_f
    assert_equal 8, high_ship.overall_score.to_f
    assert_operator high_ship.overall_percentile, :>, low_ship.tap(&:refresh_payout_score!).reload.overall_percentile
  end

  test "refresh_payouts! locks then issues payout for approved voting path ship" do
    ship = create_ship_event(hours: 2, vote_count: Post::ShipEvent::VOTES_REQUIRED_FOR_PAYOUT)

    assert_no_difference -> { @owner.ledger_entries.count } do
      Post::ShipEvent.refresh_payouts!
    end

    ship.reload
    assert_equal Post::ShipEvent::Payouts::PAYOUT_CURVE_VERSION, ship.payout_curve_version
    assert_not_nil ship.payout_basis_locked_at
    assert ship.payout_review_open?

    travel Post::ShipEvent::Payouts::PAYOUT_REVIEW_WINDOW + 1.minute do
      assert_difference -> { @owner.ledger_entries.count }, 1 do
        Post::ShipEvent.refresh_payouts!
      end
    end

    ship.reload
    assert ship.payout.positive?
    assert_equal ship.payout, @owner.ledger_entries.last.amount
    assert_equal "ship_event_payout", @owner.ledger_entries.last.created_by
  end

  test "refresh_payouts! skips payouts while feature flag is off" do
    Flipper.disable(:ship_event_payouts)
    ship = create_ship_event(hours: 2, vote_count: Post::ShipEvent::VOTES_REQUIRED_FOR_PAYOUT)

    assert_no_difference -> { @owner.ledger_entries.count } do
      assert_equal false, Post::ShipEvent.refresh_payouts!
    end

    assert_nil ship.reload.payout_basis_locked_at
  end

  test "refresh_payouts! does not issue payout for static prize submission" do
    ship = create_ship_event(hours: 2, vote_count: Post::ShipEvent::VOTES_REQUIRED_FOR_PAYOUT)
    Mission::Submission.create!(ship_event: ship, mission: create_mission, payout_path: "static_prize")

    assert_no_difference -> { @owner.ledger_entries.count } do
      Post::ShipEvent.refresh_payouts!
    end

    assert_nil ship.reload.payout
  end

  test "issue_payout! holds payout while recipient has vote deficit" do
    ship = create_ship_event(hours: 2, vote_count: Post::ShipEvent::VOTES_REQUIRED_FOR_PAYOUT)
    @owner.update!(vote_balance: -3)
    notified = nil

    Notifications::Payouts::VoteDeficitBlocked.stub(:notify, ->(**kwargs) { notified = kwargs }) do
      assert_no_difference -> { @owner.ledger_entries.count } do
        ship.refresh_payout_score!
        ship.issue_payout!
      end
    end

    assert_nil ship.reload.payout
    assert_equal @owner, notified[:recipient]
    assert_equal 3, notified[:params]["votes_needed"]
  end

  test "issue_payout! is idempotent" do
    ship = create_ship_event(hours: 2, vote_count: Post::ShipEvent::VOTES_REQUIRED_FOR_PAYOUT)

    ship.refresh_payout_score!
    ship.issue_payout!

    assert_difference -> { @owner.ledger_entries.count }, 1 do
      travel Post::ShipEvent::Payouts::PAYOUT_REVIEW_WINDOW + 1.minute do
        ship.issue_payout!
        ship.issue_payout!
      end
    end
  end

  test "issue_payout! pays from locked snapshot" do
    ship = create_ship_event(hours: 2, vote_count: Post::ShipEvent::VOTES_REQUIRED_FOR_PAYOUT)

    ship.refresh_payout_score!
    ship.issue_payout!
    ship.reload
    locked_payout = ship.estimated_payout
    ship.update_columns(overall_percentile: 100, payout_basis_percentile: ship.payout_basis_percentile)

    travel Post::ShipEvent::Payouts::PAYOUT_REVIEW_WINDOW + 1.minute do
      ship.issue_payout!
    end

    assert_equal locked_payout, ship.reload.payout
  end

  test "payout curve ranges from 1 to 20 stardust per hour" do
    ship = create_ship_event(hours: 2, vote_count: Post::ShipEvent::VOTES_REQUIRED_FOR_PAYOUT)

    assert_equal 1, ship.send(:dollars_per_hour_for_percentile, 0) * Rails.configuration.game_constants.tickets_per_dollar
    assert_equal 20, ship.send(:dollars_per_hour_for_percentile, 100) * Rails.configuration.game_constants.tickets_per_dollar
  end

  test "issue_payout! skips ships with zero hours" do
    ship = create_ship_event(hours: 0, vote_count: Post::ShipEvent::VOTES_REQUIRED_FOR_PAYOUT)

    assert_no_difference -> { @owner.ledger_entries.count } do
      ship.refresh_payout_score!
      ship.issue_payout!
    end

    assert_nil ship.reload.payout
  end

  private

  def create_ship_event(hours:, vote_count: 1, scores: [ 6, 6, 6, 6 ], project: nil)
    project ||= Project.create!(title: "Project #{SecureRandom.hex(4)}", created_at: 3.days.ago)
    Project::Membership.create!(project: project, user: @owner, role: :owner) unless project.users.exists?(@owner.id)
    ship_event = Post::ShipEvent.create!(
      body: "Ship it",
      uploading_attachments: true,
      certification_status: "approved",
      hours_at_ship: hours
    )
    Post.create!(project: project, user: @owner, postable: ship_event, created_at: Time.current)
    ship_event.update!(hours_at_ship: hours)
    add_votes(ship_event: ship_event, project: project, count: vote_count, scores: scores)
    ship_event
  end

  def add_votes(ship_event:, project:, count:, scores:)
    count.times do |i|
      voter = create_user(slack_id: "U#{SecureRandom.hex(8)}", display_name: "voter#{SecureRandom.hex(4)}#{i}")
      Vote.create!(
        user: voter,
        project: project,
        ship_event: ship_event,
        reason: "Strong implementation details with clear progress and thoughtful trade offs.",
        originality_score: scores[0],
        technical_score: scores[1],
        usability_score: scores[2],
        storytelling_score: scores[3]
      )
    end
  end
end
