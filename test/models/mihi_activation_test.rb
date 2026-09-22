require "test_helper"

# == Schema Information
#
# Table name: mihi_activations
#
#  id                :bigint           not null, primary key
#  activated_on      :date             not null
#  activations_count :integer          default(1), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  user_id           :bigint           not null
#
# Indexes
#
#  index_mihi_activations_on_activated_on_and_user_id  (activated_on,user_id) UNIQUE
#  index_mihi_activations_on_user_id                   (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class MihiActivationTest < ActiveSupport::TestCase
  test "repeat activations count once per Eastern day and remain auditable" do
    user = users(:one)
    now = Time.utc(2026, 9, 17, 3, 59)
    PaperTrail.request(whodunnit: user.id.to_s) do
      first = MihiActivation.record!(user: user, now: now)
      assert_equal first.id, MihiActivation.record!(user: user, now: now).id
      assert_equal 2, first.reload.activations_count
      assert_equal Date.new(2026, 9, 16), first.activated_on
      assert_equal user.id.to_s, first.versions.last.whodunnit
      next_day = MihiActivation.record!(user: user, now: now + 2.minutes)
      assert_not_equal first.id, next_day.id
    end
    stats = Admin::MegaDashboard::MihiStats.new(period: "7", now: now + 2.minutes).to_h
    assert_equal 1, stats[:today]
    assert_equal 1, stats[:unique_users]
    assert_equal 3, stats[:total]
    assert_equal 2, stats[:daily_totals]["2026-09-16"]
    assert_equal 7, stats[:daily].size
    assert_equal 0, stats[:daily]["2026-09-15"]
    assert_equal 1, stats[:daily]["2026-09-16"]
    assert_equal 1, stats[:daily]["2026-09-17"]
  end

  test "anonymous users and disabled flags cannot record activations" do
    assert_not MihiActivationPolicy.new(nil, MihiActivation).create?
    Flipper.stub(:enabled?, false) do
      assert_not MihiActivationPolicy.new(users(:one), MihiActivation).create?
    end
  end
end
