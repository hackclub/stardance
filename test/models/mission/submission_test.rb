require "test_helper"

# == Schema Information
#
# Table name: mission_submissions
#
#  id                               :bigint           not null, primary key
#  claim_expires_at                 :datetime
#  claimed_at                       :datetime
#  deleted_at                       :datetime
#  payout_path                      :string           not null
#  pending_at                       :datetime
#  rejection_message                :text
#  reviewed_at                      :datetime
#  status                           :string           not null
#  submission_guide_acknowledged_at :datetime
#  created_at                       :datetime         not null
#  updated_at                       :datetime         not null
#  chosen_prize_id                  :bigint
#  mission_id                       :bigint           not null
#  reviewed_by_id                   :bigint
#  ship_event_id                    :bigint           not null
#  shop_order_id                    :bigint
#
# Indexes
#
#  idx_mission_submissions_on_status_claim_expires     (status,claim_expires_at)
#  index_mission_submissions_active_per_ship_event     (ship_event_id) UNIQUE WHERE (deleted_at IS NULL)
#  index_mission_submissions_on_chosen_prize_id        (chosen_prize_id)
#  index_mission_submissions_on_deleted_at             (deleted_at)
#  index_mission_submissions_on_mission_id             (mission_id)
#  index_mission_submissions_on_mission_id_and_status  (mission_id,status)
#  index_mission_submissions_on_reviewed_by_id         (reviewed_by_id)
#  index_mission_submissions_on_ship_event_id          (ship_event_id)
#  index_mission_submissions_on_shop_order_id          (shop_order_id)
#  index_mission_submissions_on_status_and_created_at  (status,created_at)
#  index_mission_submissions_on_status_and_pending_at  (status,pending_at)
#  index_mission_submissions_with_shop_order           (shop_order_id) WHERE (shop_order_id IS NOT NULL)
#
# Foreign Keys
#
#  fk_rails_...  (chosen_prize_id => mission_prizes.id)
#  fk_rails_...  (mission_id => missions.id)
#  fk_rails_...  (reviewed_by_id => users.id)
#  fk_rails_...  (ship_event_id => post_ship_events.id)
#  fk_rails_...  (shop_order_id => shop_orders.id)
#
class Mission::SubmissionTest < ActiveSupport::TestCase
  setup do
    @builder = User.create!(email: "builder-#{SecureRandom.hex(4)}@example.test",
                            display_name: "builder-#{SecureRandom.hex(4)}",
                            slack_id: "U#{SecureRandom.hex(8)}")
    @project = Project.create!(title: "Queue Age Project")
    @project.memberships.create!(user: @builder, role: :owner)
    @mission = create_mission
    @project.mission_attachments.create!(mission: @mission)
  end

  test "certifying stamps pending_at with the queue entry time" do
    submission = ship_to_mission!(@project, @builder, @mission)
    assert_nil submission.pending_at

    travel 2.days do
      submission.certify!
      assert_in_delta Time.current, submission.reload.pending_at, 1.second
    end
  end

  test "undo restamps pending_at so queue age counts from the last review" do
    submission = ship_to_mission!(@project, @builder, @mission)
    submission.certify!
    first_entry = submission.reload.pending_at

    travel 3.days do
      submission.approve!
      submission.undo!
      assert_operator submission.reload.pending_at, :>, first_entry
      assert_in_delta Time.current, submission.pending_at, 1.second
    end
  end

  test "queue_entered_at falls back to created_at when pending_at is unset" do
    submission = ship_to_mission!(@project, @builder, @mission, status: "pending")
    assert_nil submission.pending_at
    assert_equal submission.created_at, submission.queue_entered_at

    submission.update_column(:pending_at, 1.hour.ago)
    assert_equal submission.pending_at, submission.reload.queue_entered_at
  end
end
