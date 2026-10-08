module Project::HackatimeDevlogResync
  extend ActiveSupport::Concern

  def resync_devlogs_from_hackatime_later
    Project::ResyncDevlogsFromHackatimeJob.perform_later(self)
  end

  def resync_devlogs_from_hackatime_now(audit: false)
    with_advisory_lock!("resync_devlogs_from_hackatime", timeout_seconds: 10) do
      old_duration = reload.duration_seconds if audit
      result = resync_devlogs_from_hackatime(audit: audit)
      if audit
        versions.create!(
          event: result[:unavailable_devlog_ids].any? ? "hackatime_resync_incomplete" : "hackatime_resync_completed",
          whodunnit: PaperTrail.request.whodunnit,
          object_changes: { "duration_seconds" => [ old_duration, duration_seconds ], "resync" => result.stringify_keys }.to_yaml
        )
      end
      result
    end
  end

  private
    def resync_devlogs_from_hackatime(audit:)
      keys = hackatime_keys.sort
      result = { synced: 0, skipped: 0, unavailable_devlog_ids: [] }
      if keys.any?
        resync_each_devlog_from_hackatime(keys, result, audit: audit)
        recalculate_duration_seconds!
        ship_events.find_each(&:recalculate_hours_at_ship)
      end
      result
    end

    def resync_each_devlog_from_hackatime(keys, result, audit:)
      devlog_posts_for_hackatime_resync.each do |post|
        if devlog = Post::Devlog.unscoped.find_by(id: post.postable_id)
          status = resync_devlog_from_hackatime(devlog, post, keys, audit: audit)
          if status == :unavailable
            result[:unavailable_devlog_ids] << devlog.id
          else
            result[status] += 1
          end
        end
      end
    end

    def devlog_posts_for_hackatime_resync
      posts.where(postable_type: "Post::Devlog").order(:created_at, :id)
    end

    def resync_devlog_from_hackatime(devlog, post, keys, audit:)
      return :skipped if %w[test journal-import].include?(devlog.hackatime_projects_key_snapshot)

      seconds = hackatime_seconds_for_devlog(devlog, post, keys)
      return :unavailable if seconds.nil?

      devlog.with_lock do
        changes = {
          "duration_seconds" => [ devlog.duration_seconds, seconds ],
          "hackatime_project_names_snapshot" => [ devlog.hackatime_project_names_snapshot, keys ]
        }
        devlog.update_columns(duration_seconds: seconds, hackatime_project_names_snapshot: keys,
          hackatime_pulled_at: Time.current, synced_at: nil)
        if audit
          PaperTrail::Version.create!(item: devlog, event: "hackatime_resync", whodunnit: PaperTrail.request.whodunnit,
            object_changes: changes.to_yaml)
        end
      end
      :synced
    end

    def hackatime_seconds_for_devlog(devlog, post, keys)
      if identity = post.user&.hackatime_identity
        HackatimeService.fetch_total_seconds_for_projects(
          identity.uid,
          keys,
          start_date: devlog_window_start(devlog.created_at).iso8601,
          end_date: devlog.created_at.iso8601,
          access_token: identity.access_token
        )
      end
    end
end
