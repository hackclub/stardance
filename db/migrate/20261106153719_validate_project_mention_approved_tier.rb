class ValidateProjectMentionApprovedTier < ActiveRecord::Migration[8.1]
  def change
    validate_check_constraint :project_mentions, name: "project_mentions_approved_tier"
  end
end
