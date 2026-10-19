# == Schema Information
#
# Table name: project_languages
#
#  id             :bigint           not null, primary key
#  error_message  :text
#  language_stats :jsonb
#  last_synced_at :datetime
#  status         :integer          default("pending"), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  project_id     :bigint           not null
#
# Indexes
#
#  index_project_languages_on_language_stats     (language_stats) USING gin
#  index_project_languages_on_last_synced_at     (last_synced_at)
#  index_project_languages_on_project_id_unique  (project_id) UNIQUE
#  index_project_languages_on_status             (status)
#
# Foreign Keys
#
#  fk_rails_...  (project_id => projects.id)
#
class ProjectLanguage < ApplicationRecord
  belongs_to :project

  enum :status, {
    pending: 0,
    synced: 1,
    failed: 2
  }

  validates :status, presence: true

  def mark_sync_success!(stats)
    update!(
      status: :synced,
      language_stats: stats,
      last_synced_at: Time.current,
      error_message: nil
    )
  end

  def mark_sync_failed!(error)
    update!(
      status: :failed,
      error_message: error.to_s,
      last_synced_at: Time.current
    )
  end

  def total_bytes
    language_stats&.values&.sum || 0
  end

  def language_percentages
    return {} if total_bytes.zero?

    language_stats.transform_values { |bytes| (bytes.to_f / total_bytes * 100).round(2) }
  end
end
