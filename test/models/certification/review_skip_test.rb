require "test_helper"

# == Schema Information
#
# Table name: certification_review_skips
#
#  id              :bigint           not null, primary key
#  reviewable_type :string           not null
#  skipped_at      :datetime         not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  reviewable_id   :bigint           not null
#  user_id         :bigint           not null
#
# Indexes
#
#  index_certification_review_skips_on_reviewable  (reviewable_type,reviewable_id)
#  index_certification_review_skips_on_user_id     (user_id)
#  index_review_skips_unique_reviewer_reviewable   (user_id,reviewable_type,reviewable_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class Certification::ReviewSkipTest < ActiveSupport::TestCase
  setup do
    @reviewer = create_user(slack_id: "U_SKIP_REV", display_name: "skip-reviewer")
    @ship = ::Certification::Ship.create!(project: Project.create!(title: "Skip bot"), status: :pending)
  end

  test "record! stamps a skip for the reviewer and submission" do
    freeze_time do
      skip = ::Certification::ReviewSkip.record!(user: @reviewer, reviewable: @ship)

      assert_equal @reviewer, skip.user
      assert_equal @ship, skip.reviewable
      assert_equal Time.current, skip.skipped_at
    end
  end

  test "record! refreshes the clock instead of piling up rows" do
    first = travel_to(3.hours.ago) { ::Certification::ReviewSkip.record!(user: @reviewer, reviewable: @ship) }

    assert_no_difference -> { ::Certification::ReviewSkip.count } do
      ::Certification::ReviewSkip.record!(user: @reviewer, reviewable: @ship)
    end
    assert_operator first.reload.skipped_at, :>, 1.minute.ago
  end

  test "active excludes skips older than the cooldown" do
    fresh = ::Certification::ReviewSkip.record!(user: @reviewer, reviewable: @ship)
    stale_ship = ::Certification::Ship.create!(project: Project.create!(title: "Stale bot"), status: :pending)
    stale = travel_to((::Certification::ReviewSkip::SKIP_COOLDOWN + 1.minute).ago) do
      ::Certification::ReviewSkip.record!(user: @reviewer, reviewable: stale_ship)
    end

    active_ids = ::Certification::ReviewSkip.active.pluck(:id)
    assert_includes active_ids, fresh.id
    assert_not_includes active_ids, stale.id
  end

  test "not_skipped_by hides a recently skipped submission from that reviewer only" do
    ::Certification::ReviewSkip.record!(user: @reviewer, reviewable: @ship)
    other = create_user(slack_id: "U_SKIP_REV2", display_name: "skip-reviewer-2")

    assert_not ::Certification::Ship.not_skipped_by(@reviewer).exists?(id: @ship.id)
    assert ::Certification::Ship.not_skipped_by(other).exists?(id: @ship.id)
  end

  test "not_skipped_by offers a submission again once its skip has expired" do
    travel_to((::Certification::ReviewSkip::SKIP_COOLDOWN + 1.minute).ago) do
      ::Certification::ReviewSkip.record!(user: @reviewer, reviewable: @ship)
    end

    assert ::Certification::Ship.not_skipped_by(@reviewer).exists?(id: @ship.id)
  end
end
