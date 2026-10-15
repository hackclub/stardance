class SyncProjectLanguagesJob < ApplicationJob
  queue_as :literally_whenever

  def perform
    projects = Project.needs_language_sync.limit(10).to_a
    return if projects.empty?

    Rails.logger.info "[SyncProjectLanguages] Syncing #{projects.count} projects"

    results = projects.filter_map { |project| sync_one(project) }
    batch_upsert(results) if results.any?
  end

  private

  def sync_one(project)
    host = GitHost::Base.for(project.repo_url)
    unless host&.respond_to?(:fetch_languages)
      return {
        project_id: project.id,
        status: :failed,
        language_stats: {},
        error_message: "Unsupported or missing repository URL",
        last_synced_at: Time.current
      }
    end

    stats = host.fetch_languages
    unless stats.is_a?(Hash)
      return {
        project_id: project.id,
        status: :failed,
        language_stats: {},
        error_message: "Failed to fetch languages from #{host.provider_display_name}",
        last_synced_at: Time.current
      }
    end

    Rails.logger.info "[SyncProjectLanguages] Project #{project.id}: #{stats.keys.join(', ')}"

    {
      project_id: project.id,
      status: :synced,
      language_stats: stats,
      error_message: nil,
      last_synced_at: Time.current
    }
  rescue => e
    Rails.logger.error "[SyncProjectLanguages] Project #{project.id} error: #{e.message}"

    {
      project_id: project.id,
      status: :failed,
      language_stats: {},
      error_message: e.message,
      last_synced_at: Time.current
    }
  end

  def batch_upsert(results)
    upsert_data = results.map do |r|
      {
        project_id: r[:project_id],
        status: ProjectLanguage.statuses[r[:status]],
        language_stats: r[:language_stats],
        error_message: r[:error_message],
        last_synced_at: r[:last_synced_at],
        created_at: Time.current
      }
    end

    ProjectLanguage.upsert_all(
      upsert_data,
      unique_by: :index_project_languages_on_project_id_unique,
      update_only: [ :status, :language_stats, :error_message, :last_synced_at ]
    )

    Rails.logger.info "[SyncProjectLanguages] Upserted #{upsert_data.count} records"
  end
end
