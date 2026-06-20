require "test_helper"

class ForwardLookoutHeartbeatsJobTest < ActiveJob::TestCase
  setup do
    @user = create_user(slack_id: "U_FWD", display_name: "fwd")
    # A Hackatime identity with a token is required to forward. Stub fetch_stats
    # so the after_create_commit sync doesn't hit the network.
    HackatimeService.stub(:fetch_stats, nil) do
      @user.identities.create!(provider: "hackatime", uid: "ht-fwd", access_token: "ht-secret")
    end
    @project = Project.create!(title: "Robot arm", hardware_stage: "build")
    @session = @project.lookout_sessions.create!(user: @user, token: "tok-fwd", status: "stopped")
  end

  test "forwards capture timestamps to the chosen Hackatime project as Lookout heartbeats" do
    captured = nil
    push = ->(api_key:, heartbeats:) { captured = { key: api_key, beats: heartbeats }; true }

    # The job first exchanges the OAuth token for the user's API key.
    HackatimeService.stub(:fetch_api_key, "ht-api-key") do
      LookoutService.stub(:fetch_timings, { "timestamps" => [ "2026-06-03T10:00:00Z", "2026-06-03T10:01:00Z" ] }) do
        HackatimeService.stub(:push_heartbeats, push) do
          ForwardLookoutHeartbeatsJob.perform_now(@session.id, "Chosen Project")
        end
      end
    end

    assert_equal "ht-api-key", captured[:key]
    assert_equal 2, captured[:beats].size
    beat = captured[:beats].first
    assert_equal "Chosen Project", beat[:project]
    assert_equal "Lookout", beat[:editor]
    assert_equal "Lookout", beat[:language]
    assert_equal @session.token, beat[:entity]
    assert_equal Time.utc(2026, 6, 3, 10, 0, 0).to_i, beat[:time]

    # The chosen Hackatime project is auto-linked to the Stardance project.
    link = User::HackatimeProject.find_by(user: @user, name: "Chosen Project")
    assert link, "expected the chosen Hackatime project to be auto-linked"
    assert_equal @project.id, link.project_id
  end

  test "falls back to the project's recorder name when no destination is given" do
    captured = nil
    push = ->(api_key:, heartbeats:) { captured = { beats: heartbeats }; true }

    HackatimeService.stub(:fetch_api_key, "ht-api-key") do
      LookoutService.stub(:fetch_timings, { "timestamps" => [ "2026-06-03T10:00:00Z" ] }) do
        HackatimeService.stub(:push_heartbeats, push) do
          ForwardLookoutHeartbeatsJob.perform_now(@session.id)
        end
      end
    end

    fallback = @project.hackatime_recorder_name
    assert_equal fallback, captured[:beats].first[:project]
    assert User::HackatimeProject.find_by(user: @user, name: fallback)
  end

  test "does not steal a Hackatime project already linked to another project" do
    other_project = Project.create!(title: "Other rig", hardware_stage: "build")
    @user.hackatime_projects.create!(name: "Shared", project: other_project)

    HackatimeService.stub(:fetch_api_key, "ht-api-key") do
      LookoutService.stub(:fetch_timings, { "timestamps" => [ "2026-06-03T10:00:00Z" ] }) do
        HackatimeService.stub(:push_heartbeats, true) do
          ForwardLookoutHeartbeatsJob.perform_now(@session.id, "Shared")
        end
      end
    end

    # The link stays with the project it was already attached to.
    assert_equal other_project.id, User::HackatimeProject.find_by(user: @user, name: "Shared").project_id
  end

  test "does not link the project when the heartbeat push fails" do
    HackatimeService.stub(:fetch_api_key, "ht-api-key") do
      LookoutService.stub(:fetch_timings, { "timestamps" => [ "2026-06-03T10:00:00Z" ] }) do
        HackatimeService.stub(:push_heartbeats, false) do
          ForwardLookoutHeartbeatsJob.perform_now(@session.id, "Robot arm - Hackatime")
        end
      end
    end

    assert_nil User::HackatimeProject.find_by(user: @user, name: "Robot arm - Hackatime")
  end

  test "does nothing without a linked Hackatime account" do
    other = create_user(slack_id: "U_NOHT", display_name: "noht")
    session = @project.lookout_sessions.create!(user: other, token: "tok-noht", status: "stopped")

    called = false
    HackatimeService.stub(:push_heartbeats, ->(**) { called = true }) do
      LookoutService.stub(:fetch_timings, { "timestamps" => [ "2026-06-03T10:00:00Z" ] }) do
        ForwardLookoutHeartbeatsJob.perform_now(session.id)
      end
    end

    assert_not called
  end
end
