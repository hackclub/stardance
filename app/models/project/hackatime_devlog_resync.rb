module Project::HackatimeDevlogResync
  extend ActiveSupport::Concern

  def resync_devlogs_from_hackatime_later
    Project::ResyncDevlogsFromHackatimeJob.perform_later(self)
  end

  def resync_devlogs_from_hackatime_now
    with_advisory_lock!("resync_devlogs_from_hackatime", timeout_seconds: 10) do
      resync_devlogs_from_hackatime
    end
  end

  private
    def resync_devlogs_from_hackatime
      keys = hackatime_keys.sort
      if keys.any?
        resync_each_devlog_from_hackatime(keys)
        recalculate_duration_seconds!
        ship_events.find_each(&:recalculate_hours_at_ship)
      end
    end

    def resync_each_devlog_from_hackatime(keys)
      devlog_posts_for_hackatime_resync.each do |post|
        if devlog = Post::Devlog.unscoped.find_by(id: post.postable_id)
          resync_devlog_from_hackatime(devlog, post, keys)
        end
      end
    end

    def devlog_posts_for_hackatime_resync
      posts.where(postable_type: "Post::Devlog").order(:created_at, :id)
    end

    def resync_devlog_from_hackatime(devlog, post, keys)
      if seconds = hackatime_seconds_for_devlog(devlog, post, keys)
        devlog.update_columns(
          duration_seconds: seconds,
          hackatime_projects_key_snapshot: keys.join(","),
          hackatime_pulled_at: Time.current,
          synced_at: nil
        )
      end
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
