class AddSubmissionGuideAckToMissionSubmissions < ActiveRecord::Migration[8.1]
  def change
    add_column :mission_submissions, :submission_guide_acknowledged_at, :datetime
  end
end
