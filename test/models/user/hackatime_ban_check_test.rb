require "test_helper"

# Hackatime blocks a banned user's own token, and the public stats fallback
# fails when their stats are private, so the ban has to be read another way.
class User::HackatimeBanCheckTest < ActiveSupport::TestCase
  include UserFactory

  setup do
    @user = create_user(slack_id: "u-ht-check", display_name: "htcheck")
    @user.identities.create!(provider: "hackatime", uid: "ht-check", access_token: "ht-secret")
  end

  test "a ban is read from the trust level when stats cannot be fetched" do
    HackatimeService.stub(:fetch_stats, nil) do
      HackatimeService.stub(:fetch_trust_level, "red") { @user.try_sync_hackatime_data!(force: true) }
    end

    assert @user.reload.banned?
  end

  test "a clean trust level leaves the user alone when stats cannot be fetched" do
    HackatimeService.stub(:fetch_stats, nil) do
      HackatimeService.stub(:fetch_trust_level, "green") { @user.try_sync_hackatime_data!(force: true) }
    end

    assert_not @user.reload.banned?
  end

  test "an undeterminable ban status is reported to Sentry and treated as not banned" do
    reports = []

    HackatimeService.stub(:fetch_stats, nil) do
      HackatimeService.stub(:fetch_trust_level, nil) do
        Sentry.stub(:capture_message, ->(message, **) { reports << message }) { @user.try_sync_hackatime_data!(force: true) }
      end
    end

    assert_equal [ "Could not determine Hackatime ban status" ], reports
    assert_not @user.reload.banned?
  end

  test "stats that load are trusted without a second lookup" do
    trust_lookup = ->(*) { flunk "trust level should not be fetched when stats load" }

    HackatimeService.stub(:fetch_stats, { banned: false, projects: {} }) do
      HackatimeService.stub(:fetch_trust_level, trust_lookup) { @user.try_sync_hackatime_data!(force: true) }
    end

    assert_not @user.reload.banned?
  end
end
