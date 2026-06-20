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

  private

  def add_legitimate_votes(ship_event:, project:, count:)
    records = count.times.map do |i|
      voter = User.create!(email: "voter-#{SecureRandom.hex(6)}-#{i}@example.com", display_name: "Voter #{i}", slack_id: "U#{SecureRandom.hex(8)}")
      {
        user_id: voter.id,
        project_id: project.id,
        ship_event_id: ship_event.id,
        reason: "Strong implementation details with clear progress and thoughtful trade-offs.",
        originality_score: 6,
        technical_score: 6,
        usability_score: 6,
        storytelling_score: 6,
        suspicious: false,
        time_taken_to_vote: 30,
        demo_url_clicked: true,
        repo_url_clicked: true,
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    Vote.insert_all!(records)
  end
end
