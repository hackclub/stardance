class OneTime::BackfillHackatimeDevlogsJob < ApplicationJob
  queue_as :literally_whenever

  def perform(dry_run: true, batch_size: 200, project_ids: nil)
    @batch_size = batch_size
    @project_ids = project_ids

    if dry_run
      log_summary(dry_run_summary)
    else
      backfill
    end
  end

  private
    attr_reader :batch_size, :project_ids

    def dry_run_summary
      devlogs = candidate_devlogs.count
      {
        dry_run: true,
        projects: candidates.count,
        devlogs: devlogs
      }
    end

    def candidates
      relation = Project.joins(:hackatime_projects, :devlog_posts).distinct
      project_ids ? relation.where(id: project_ids) : relation
    end

    def candidate_devlogs
      Post.where(project_id: candidates.select(:id), postable_type: "Post::Devlog")
    end

    def backfill
      summary = { dry_run: false, projects: 0, failed: [] }

      candidates.find_each(batch_size: batch_size) do |project|
        resync_project(project, summary)
      end

      log_summary(summary)
    end

    def resync_project(project, summary)
      project.resync_devlogs_from_hackatime_now
      summary[:projects] += 1
    rescue => error
      summary[:failed] << project.id
      Rails.logger.error("[BackfillHackatimeDevlogs] Project #{project.id} failed: #{error.message}")
    end

    def log_summary(summary)
      Rails.logger.info("[BackfillHackatimeDevlogs] #{summary.inspect}")
      summary
    end
end
