require "test_helper"

class User::FunnelTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "a brand-new user is nudged to onboard, stuck since signup" do
    created = @user.created_at
    stub_funnel(signed_up: created) do
      assert_equal :onboarded, @user.funnel_stage
      assert_equal created, @user.funnel_stage_entered_at
    end
  end

  test "reports the first incomplete step and when they last progressed" do
    onboarded_at = 4.days.ago
    stub_funnel(signed_up: 10.days.ago, onboarded: onboarded_at) do
      assert_equal :project_created, @user.funnel_stage
      assert_equal onboarded_at, @user.funnel_stage_entered_at
    end
  end

  test "an out-of-order step does not skip an earlier gap" do
    hca_at = 2.days.ago
    # HCA linked but no project — they should still be nudged to create one,
    # and be "stuck" since their most recent progress (linking HCA).
    stub_funnel(signed_up: 8.days.ago, onboarded: 6.days.ago, hca_linked: hca_at) do
      assert_equal :project_created, @user.funnel_stage
      assert_equal hca_at, @user.funnel_stage_entered_at
    end
  end

  test "a user who finished every step is :completed" do
    stub_funnel(User::Funnel::STAGES.index_with { 1.day.ago }) do
      assert_equal :completed, @user.funnel_stage
    end
  end

  private

  # The per-step timestamps come from six different associations; stub them so
  # the test exercises the gap logic, not fixture plumbing. Assertions run
  # inside the yielded block, while the stub is in place.
  def stub_funnel(timestamps, &block)
    full = User::Funnel::STAGES.index_with { nil }.merge(timestamps)
    @user.stub(:funnel_step_timestamps, full, &block)
  end
end
