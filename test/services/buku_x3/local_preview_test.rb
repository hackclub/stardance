require "test_helper"

class BukuX3LocalPreviewTest < ActiveSupport::TestCase
  setup do
    Flipper.enable(:bukux2_preview_complete)
    Flipper.enable(:bukux3)
  end

  teardown do
    Flipper.disable(:bukux2_preview_complete)
    Flipper.disable(:bukux3)
  end

  test "development override fills the old bar without fake ships" do
    Rails.stub(:env, ActiveSupport::StringInquirer.new("development")) do
      assert_equal 5000, RocketProgress.snapshot.hours
      assert_equal 0, RocketProgress.snapshot.user_hours
      assert_no_difference "Certification::Ysws.count" do
        event = BukuX3::Refresh.call
        assert event.active?
        assert_empty event.contributions
        assert_equal 25, event.percent
      end
    end
  end

  test "production ignores the override flag" do
    Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
      assert_not RocketProgress.preview_complete?
      assert_equal 0, RocketProgress.snapshot.hours
    end
  end

  test "turning off the override restores actual rocket hours" do
    Rails.stub(:env, ActiveSupport::StringInquirer.new("development")) do
      Flipper.disable(:bukux2_preview_complete)
      assert_equal 0, RocketProgress.snapshot.hours
    end
  end
end
