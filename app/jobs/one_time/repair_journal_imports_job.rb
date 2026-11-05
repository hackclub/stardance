# Deploy the journal-import resync guard to web and worker processes first.
# Restores imports only when the original audit and Hackatime resync metadata
# agree; ambiguous records and deleted projects are reported for manual review.
# Also fixes cached totals when the journal records themselves are intact.
# Each project is atomic and audited. Payouts and review decisions are unchanged.
#
# Dry run (no writes or jobs):
#   OneTime::RepairJournalImportsJob.perform_now
# Apply a reviewed subset:
#   OneTime::RepairJournalImportsJob.perform_now(dry_run: false, project_ids: [19306, 23805])
class OneTime::RepairJournalImportsJob < ApplicationJob
  queue_as :literally_whenever

  def perform(dry_run: true, project_ids: nil)
    raise ArgumentError, "dry_run must be true or false" unless [ true, false ].include?(dry_run)

    summary = { dry_run: dry_run, projects: [], skipped: [] }
    projects = Project.with_deleted.where(id: Post.of_devlogs
      .where("postable_id::text IN (?)", import_versions.select(:item_id)).select(:project_id))
    projects = projects.where(id: project_ids) unless project_ids.nil?

    projects.find_each do |project|
      # Serialize with the regular resync, and with posts touching the project.
      project.with_advisory_lock!("resync_devlogs_from_hackatime", timeout_seconds: 10) do
        project.with_lock("FOR UPDATE NOWAIT", requires_new: true) do
          if project.deleted?
            summary[:skipped] << { project_id: project.id, reason: "deleted project" }
            next
          end

          # Normal edits and payouts lock children before touching their project.
          # Never wait for those children while holding the project lock.
          posts = project.posts.order(:id).lock("FOR UPDATE NOWAIT").to_a
          Post::Devlog.with_deleted.where(id: posts.select { |post| post.postable_type == "Post::Devlog" }.map(&:postable_id))
            .order(:id).lock("FOR UPDATE NOWAIT").load
          Post::ShipEvent.where(id: posts.select { |post| post.postable_type == "Post::ShipEvent" }.map(&:postable_id))
            .order(:id).lock("FOR UPDATE NOWAIT").load

          repairs = journal_repairs(project, summary[:skipped])
          seconds = project.calculate_duration_seconds + repairs.sum do |repair|
            devlog = repair[:devlog]
            devlog.deleted? ? 0 : repair[:attributes][:duration_seconds] - devlog.duration_seconds.to_i
          end
          next if repairs.empty? && seconds == project.duration_seconds

          plan = {
            project_id: project.id,
            duration_seconds: [ project.duration_seconds, seconds ],
            devlogs: repairs.map do |repair|
              { devlog_id: repair[:devlog].id, import_version_id: repair[:version].id,
                duration_seconds: [ repair[:devlog].duration_seconds, repair[:attributes][:duration_seconds] ] }
            end,
            ship_event_ids: project.ship_events.pluck(:id)
          }

          unless dry_run
            PaperTrail.request(whodunnit: self.class.name) do
              repairs.each do |repair|
                audit_update!(repair[:devlog], repair[:attributes], import_version: repair[:version])
              end
              audit_update!(project, { duration_seconds: seconds })
              project.ship_events.find_each do |ship|
                ship.paper_trail_event = "repair_journal_import"
                ship.recalculate_hours_at_ship
              end
            end
          end

          summary[:projects] << plan
        end
      end
    rescue ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked, WithAdvisoryLock::FailedToAcquireLock
      summary[:skipped] << { project_id: project.id, reason: "busy project; retry after the current edit or payout finishes" }
    end

    Rails.logger.info "[RepairJournalImports] #{summary.inspect}"
    summary
  end

  private

  def import_versions
    PaperTrail::Version.where(item_type: "Post::Devlog", event: "journal_import")
  end

  def journal_repairs(project, skipped)
    versions = import_versions.where(item_id: project.devlog_posts.pluck(:postable_id).map(&:to_s)).group_by(&:item_id)
    versions.filter_map do |devlog_id, sources|
      begin
        raise ArgumentError, "multiple import audits" unless sources.one?

        source = sources.first
        devlog = Post::Devlog.with_deleted.lock("FOR UPDATE NOWAIT").find_by(id: devlog_id)
        raise ArgumentError, "missing devlog" unless devlog

        seconds = imported_seconds(source)
        intact_import = devlog.duration_seconds == seconds && devlog.hackatime_projects_key_snapshot == "journal-import"
        next if intact_import && devlog.hackatime_project_names_snapshot == []

        if !intact_import && (devlog.hackatime_projects_key_snapshot == "journal-import" || devlog.hackatime_pulled_at.nil?)
          raise ArgumentError, "duration or marker changed without Hackatime resync evidence"
        end

        later_changes = PaperTrail::Version.where(item_type: "Post::Devlog", item_id: devlog_id)
          .where("created_at > ?", source.created_at)
          .where.not(event: %w[repair_journal_import hackatime_resync])
        if later_changes.any? { |version| audit_payload(version).key?("duration_seconds") }
          raise ArgumentError, "duration has a later audited edit"
        end

        { devlog: devlog, version: source, attributes: {
          duration_seconds: seconds, hackatime_projects_key_snapshot: "journal-import", hackatime_project_names_snapshot: [],
          hackatime_pulled_at: nil, synced_at: nil
        } }
      rescue ArgumentError, TypeError, KeyError, Psych::Exception => error
        skipped << { project_id: project.id, devlog_id: devlog_id, reason: error.message }
        nil
      end
    end
  end

  def imported_seconds(version)
    payload = audit_payload(version)
    raise ArgumentError, "invalid import source" unless payload[:source] == "journal_import"

    hours = Float(payload.fetch(:hours))
    raise ArgumentError, "invalid imported hours" unless hours.finite? && hours >= 0.25

    (hours * 3600).to_i
  end

  def audit_payload(version)
    payload = version.object_changes
    payload = YAML.safe_load(payload, permitted_classes: [ Symbol ], aliases: false) if payload.is_a?(String)
    raise ArgumentError, "invalid audit" unless payload.is_a?(Hash)

    payload.with_indifferent_access
  end

  def audit_update!(record, attributes, import_version: nil)
    changes = attributes.each_with_object({}) do |(name, value), result|
      result[name] = [ record[name], value ] unless record[name] == value
    end
    return if changes.empty?

    record.update_columns(attributes)
    changes[:journal_import_version_id] = [ nil, import_version.id ] if import_version
    PaperTrail::Version.create!(
      item_type: record.class.name, item_id: record.id, event: "repair_journal_import",
      whodunnit: self.class.name, object_changes: changes
    )
  end
end
