class OneTime::FixDuplicateDevlogTimeJob < ApplicationJob
  queue_as :literally_whenever

  def perform
    # This recalculates project time based on anything affected by https://github.com/hackclub/stardance/pull/827
    # We only look for cases of projects where the devlog time is greater than the hackatime time,
    # not all cases of devlogs being incorrect.
    # If a devlog got extra time but the user has since logged that extra time,
    # no harm no foul.

    projects_fixed = 0
    devlogs_recalculated = 0

    Project.includes(:hackatime_projects, :memberships).find_each do |project|
      next if project.hackatime_projects.empty?

      owner = project.memberships.find { |m| m.role == "owner" }&.user
      next unless owner

      hackatime_result = owner.try_sync_hackatime_data!
      next unless hackatime_result

      hackatime_seconds = project.hackatime_projects.sum { |hp| hackatime_result[:projects][hp.name].to_i }
      devlog_seconds = project.calculate_duration_seconds

      if devlog_seconds > hackatime_seconds
        Rails.logger.info "[FixDuplicateDevlogTime] Project #{project.id} (#{project.title}): devlog_seconds=#{devlog_seconds}, hackatime_seconds=#{hackatime_seconds}"

        project.devlogs.order(:created_at).each do |post|
          devlog = post.postable
          next unless devlog

          old_duration = devlog.duration_seconds
          devlog.recalculate_seconds_coded
          devlog.reload

          if old_duration != devlog.duration_seconds
            Rails.logger.info "  - Devlog #{devlog.id}: #{old_duration} -> #{devlog.duration_seconds}"
            devlogs_recalculated += 1
          end
        end

        project.recalculate_duration_seconds!
        projects_fixed += 1
      end
    end

    Rails.logger.info "[FixDuplicateDevlogTime] Complete. Fixed #{projects_fixed} projects, recalculated #{devlogs_recalculated} devlogs."
  end
end
