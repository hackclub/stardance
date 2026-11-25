require "test_helper"

class User::SyncHackatimeDataJobTest < ActiveJob::TestCase
  setup do
    @user = create_user(slack_id: "U_SHDJ_USER", display_name: "shdj_user")

    HackatimeService.stub(:fetch_stats, nil) do
      @user.identities.create!(provider: "hackatime", uid: "ht-shdj-user", access_token: "user-token")
    end
  end

  test "records the user's hackatime project names" do
    HackatimeService.stub(:fetch_stats, { projects: { "nebula" => 60 }, banned: false }) do
      User::SyncHackatimeDataJob.perform_now(@user.id)
    end

    assert User::HackatimeProject.exists?(user: @user, name: "nebula")
    assert_not @user.reload.banned?
  end

  test "bans a user who is banned on hackatime" do
    HackatimeService.stub(:fetch_stats, { projects: {}, banned: true }) do
      User::SyncHackatimeDataJob.perform_now(@user.id)
    end

    @user.reload
    assert @user.banned?
    assert_equal User::HackatimeSync::HACKATIME_BAN_REASON, @user.banned_reason
  end

  test "does nothing for a user that no longer exists" do
    assert_nothing_raised { User::SyncHackatimeDataJob.perform_now(-1) }
  end
end
