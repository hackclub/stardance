# Hardware builders log their build time through Lapse, and Lapse files every
# timelapse under a Hackatime project key. So each member of a hardware project
# needs a Hackatime project of the right name to exist before they can record
# anything against it.
#
# Runs off Project rather than from a controller, because a project can turn
# hardware from five places: create with a hardware_stage, create onto a hardware
# mission, edit, the setup wizard, and Mission::MigrateProjectsToHardwareJob
# converting a whole mission at once.
#
# It also runs on rename, and that is the common case rather than the exception:
# both create flows post a placeholder title, so a project is usually named
# after it turns hardware, not before. A rename adds the new name alongside the
# old one instead of moving the link, so time already recorded under the old
# name keeps counting toward the project.
class Project::EnsureHackatimeProjectsJob < ApplicationJob
  queue_as :literally_whenever

  # Far enough back to cover any Hackatime history, so the existence check
  # can't mistake an old project for a missing one.
  HACKATIME_EPOCH = "2015-01-01".freeze

  def perform(project_id)
    project = Project.find_by(id: project_id)
    return unless project&.hardware?
    # A project that hasn't been named yet gets seeded by the rename instead.
    return if project.placeholder_title?

    name = project.hackatime_recorder_name
    return if name.blank?
    # Hackatime treats these as buckets rather than projects and strips them
    # from stats, so a project of that name could never be found or linked.
    return if User::HackatimeProject::EXCLUDED_NAMES.include?(name)

    project.users.includes(:hackatime_identity).find_each { |user| ensure_for(user, project, name) }
  end

  private

  # Only link once the Hackatime project is known to exist for this member.
  # Linking earlier would make Project#hackatime_keys non-empty for someone with
  # no Hackatime account at all, which silently opens the devlog gate
  # (Projects::DevlogsController#require_hackatime_project) and hides the
  # "connect Hackatime" prompts.
  def ensure_for(user, project, name)
    # Already linked: nothing to seed and nothing to look up. Without this the
    # job spends a full Hackatime stats call per member on every rename and
    # every join, which the backfill multiplies into the documented rate limit.
    return if User::HackatimeProject.exists?(user: user, name: name, project: project)

    identity = user.hackatime_identity
    return if identity&.access_token.blank?

    case hackatime_project_state(identity, name)
    when :exists
      User::HackatimeProject.link(user: user, project: project, name: name)
    when :missing
      seed_and_link(user, project, name, identity)
    end
    # :unknown: the lookup failed, so we can't tell a missing project from an
    # existing one. Do nothing: seeding blind into a project that already has
    # heartbeats would score the gap since the member's last one as real coding
    # time. A later run (rename, join, or the backfill) picks it up.
  end

  def seed_and_link(user, project, name, identity)
    api_key = HackatimeService.fetch_api_key(identity.access_token)
    return if api_key.blank?

    seeded = HackatimeService.create_project(
      api_key: api_key,
      name: name,
      entity: "stardance://project/#{project.id}/hackatime-project-seed"
    )
    # Don't claim the key locally if Hackatime never got the heartbeat: the
    # link is what tells the rest of the app the project is ready to record
    # against, and Lapse would have nothing to file under.
    unless seeded
      Rails.logger.error("EnsureHackatimeProjects: seed failed for user #{user.id} project #{project.id}")
      return
    end

    User::HackatimeProject.link(user: user, project: project, name: name)
  end

  # :exists / :missing / :unknown. A name Hackatime already knows needs no
  # seeding, since the member may have been logging code time under it long before
  # the project turned hardware.
  def hackatime_project_state(identity, name)
    # Ask over all time, not the default window. fetch_stats starts at
    # HackatimeService::START_DATE, and Hackatime long predates Stardance: a
    # project whose heartbeats are all older would read as missing and get
    # seeded, which is the one case that can invent payable time (only the
    # FIRST heartbeat in a project scores zero).
    stats = HackatimeService.fetch_stats(identity.uid, start_date: HACKATIME_EPOCH,
                                                       access_token: identity.access_token)
    return :unknown if stats.blank?

    stats[:projects].key?(name) ? :exists : :missing
  end
end
