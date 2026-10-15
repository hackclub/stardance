require "test_helper"

class Project::EnsureHackatimeProjectsJobTest < ActiveJob::TestCase
  setup do
    @owner = create_user(slack_id: "U_EHP_OWNER", display_name: "ehp_owner")
    @collaborator = create_user(slack_id: "U_EHP_COLLAB", display_name: "ehp_collab")

    # fetch_stats is stubbed while linking identities so the after_create_commit
    # sync on User::Identity doesn't reach the network.
    HackatimeService.stub(:fetch_stats, nil) do
      @owner.identities.create!(provider: "hackatime", uid: "ht-owner", access_token: "owner-token")
      @collaborator.identities.create!(provider: "hackatime", uid: "ht-collab", access_token: "collab-token")
    end

    # Mirrors the real paths: the project exists with its members before it turns
    # hardware, so the transition always has someone to seed for.
    @project = Project.create!(title: "Robot arm")
    @project.memberships.create!(user: @owner, role: :owner)
    @project.memberships.create!(user: @collaborator, role: :contributor)
    @project.update!(hardware_stage: "design")
  end

  # Hackatime has no project resource, so "the project exists" means "some
  # heartbeat carries its name". Capture what we'd push.
  def seed_hackatime(existing_projects: {})
    seeded = []
    stats = existing_projects.any? ? { projects: existing_projects } : { projects: {} }

    HackatimeService.stub(:fetch_stats, stats) do
      HackatimeService.stub(:fetch_api_key, "ht-api-key") do
        HackatimeService.stub(:push_heartbeats, ->(api_key:, heartbeats:) { seeded.concat(heartbeats); true }) do
          yield
        end
      end
    end

    seeded
  end

  test "seeds a Hackatime project named after the project for every member" do
    seeded = seed_hackatime { Project::EnsureHackatimeProjectsJob.perform_now(@project.id) }

    assert_equal 2, seeded.size
    assert_equal [ "Robot arm" ], seeded.map { |beat| beat[:project] }.uniq
  end

  test "marks the heartbeat as a project-creation seed rather than real activity" do
    seeded = seed_hackatime { Project::EnsureHackatimeProjectsJob.perform_now(@project.id) }

    beat = seeded.first
    assert_equal "stardance-project-seed", beat[:plugin]
    assert_equal "Stardance", beat[:editor]
    assert_equal "stardance://project/#{@project.id}/hackatime-project-seed", beat[:entity]
  end

  test "links the Hackatime name to the project for every member" do
    seed_hackatime { Project::EnsureHackatimeProjectsJob.perform_now(@project.id) }

    [ @owner, @collaborator ].each do |user|
      link = User::HackatimeProject.find_by(user: user, name: "Robot arm")
      assert_equal @project.id, link&.project_id, "expected #{user.display_name} to be linked"
    end
  end

  test "does not seed a second time when the member already has that Hackatime project" do
    seeded = seed_hackatime(existing_projects: { "Robot arm" => 7200 }) do
      Project::EnsureHackatimeProjectsJob.perform_now(@project.id)
    end

    assert_empty seeded
    assert_equal @project.id, User::HackatimeProject.find_by(user: @owner, name: "Robot arm")&.project_id
  end

  test "is idempotent across repeated runs" do
    seed_hackatime(existing_projects: { "Robot arm" => 60 }) do
      2.times { Project::EnsureHackatimeProjectsJob.perform_now(@project.id) }
    end

    assert_equal 1, User::HackatimeProject.where(user: @owner, name: "Robot arm").count
  end

  # Seeding blind is not safe: if the member is already logging time under that
  # name, Hackatime scores the gap since their last heartbeat as real coding
  # time, so a seed would invent payable hours. A later run picks it up instead.
  test "does not seed when the Hackatime lookup fails" do
    seeded = []
    HackatimeService.stub(:fetch_stats, nil) do
      HackatimeService.stub(:fetch_api_key, "ht-api-key") do
        HackatimeService.stub(:push_heartbeats, ->(api_key:, heartbeats:) { seeded.concat(heartbeats); true }) do
          Project::EnsureHackatimeProjectsJob.perform_now(@project.id)
        end
      end
    end

    assert_empty seeded
    assert_nil User::HackatimeProject.find_by(user: @owner, name: "Robot arm")
  end

  # The link is what tells the rest of the app the project is ready to record
  # against, so claiming the name after a failed push would open the devlog gate
  # while Lapse still has nothing to file under.
  test "does not link when the seed heartbeat fails to send" do
    HackatimeService.stub(:fetch_stats, { projects: {} }) do
      HackatimeService.stub(:fetch_api_key, "ht-api-key") do
        HackatimeService.stub(:push_heartbeats, ->(api_key:, heartbeats:) { false }) do
          Project::EnsureHackatimeProjectsJob.perform_now(@project.id)
        end
      end
    end

    assert_nil User::HackatimeProject.find_by(user: @owner, name: "Robot arm")
  end

  test "never steals a Hackatime name already linked to a different project" do
    other = Project.create!(title: "Other project")
    User::HackatimeProject.create!(user: @owner, name: "Robot arm", project: other)

    seed_hackatime(existing_projects: { "Robot arm" => 60 }) do
      Project::EnsureHackatimeProjectsJob.perform_now(@project.id)
    end

    assert_equal other.id, User::HackatimeProject.find_by(user: @owner, name: "Robot arm").project_id
  end

  # Linking someone with no Hackatime account would make hackatime_keys non-empty
  # for them, which silently opens the devlog gate and hides the connect prompts.
  test "skips members with no Hackatime identity entirely" do
    stranger = create_user(slack_id: "U_EHP_NOHT", display_name: "ehp_noht")
    @project.memberships.create!(user: stranger, role: :contributor)

    seeded = seed_hackatime { Project::EnsureHackatimeProjectsJob.perform_now(@project.id) }

    assert_equal 2, seeded.size
    assert_nil User::HackatimeProject.find_by(user: stranger, name: "Robot arm")
  end

  # Hackatime strips these from stats, so such a project could never be found or
  # linked and we would re-seed junk heartbeats on every run.
  test "refuses names Hackatime reserves" do
    reserved = Project.create!(title: User::HackatimeProject::EXCLUDED_NAMES.first)
    reserved.memberships.create!(user: @owner, role: :owner)
    reserved.update!(hardware_stage: "design")

    seeded = seed_hackatime { Project::EnsureHackatimeProjectsJob.perform_now(reserved.id) }

    assert_empty seeded
    assert_nil User::HackatimeProject.find_by(user: @owner, name: reserved.title)
  end

  test "does nothing while the project still has a placeholder title" do
    unnamed = Project.create!(title: Project::DEFAULT_TITLE, hardware_stage: "design")
    unnamed.memberships.create!(user: @owner, role: :owner)

    seeded = seed_hackatime { Project::EnsureHackatimeProjectsJob.perform_now(unnamed.id) }

    assert_empty seeded
    assert_nil User::HackatimeProject.find_by(user: @owner, name: Project::DEFAULT_TITLE)
  end

  test "a rename adds the new name and keeps the old link so recorded time still counts" do
    seed_hackatime { Project::EnsureHackatimeProjectsJob.perform_now(@project.id) }
    @project.update!(title: "Robot arm mk2")

    seeded = seed_hackatime(existing_projects: { "Robot arm" => 3600 }) do
      Project::EnsureHackatimeProjectsJob.perform_now(@project.id)
    end

    assert_equal [ "Robot arm mk2" ], seeded.map { |beat| beat[:project] }.uniq
    assert_equal [ "Robot arm", "Robot arm mk2" ], @project.reload.hackatime_keys.sort
  end

  test "hackatime_keys deduplicates the per-member rows" do
    seed_hackatime { Project::EnsureHackatimeProjectsJob.perform_now(@project.id) }

    assert_equal 2, User::HackatimeProject.where(project: @project, name: "Robot arm").count
    assert_equal [ "Robot arm" ], @project.reload.hackatime_keys
  end

  test "does nothing for a project that is no longer hardware" do
    software = Project.create!(title: "Just software")
    software.memberships.create!(user: @owner, role: :owner)

    seeded = seed_hackatime { Project::EnsureHackatimeProjectsJob.perform_now(software.id) }

    assert_empty seeded
    assert_nil User::HackatimeProject.find_by(user: @owner, name: "Just software")
  end
end
