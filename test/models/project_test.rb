# == Schema Information
#
# Table name: projects
#
#  id                 :bigint           not null, primary key
#  ai_declaration     :text
#  deleted_at         :datetime
#  demo_url           :text
#  description        :text
#  devlogs_count      :integer          default(0), not null
#  duration_seconds   :integer          default(0), not null
#  marked_fire_at     :datetime
#  memberships_count  :integer          default(0), not null
#  project_categories :string           default([]), is an Array
#  project_type       :string
#  readme_url         :text
#  repo_url           :text
#  ship_status        :string           default("draft")
#  shipped_at         :datetime
#  synced_at          :datetime
#  title              :string           not null
#  tutorial           :boolean          default(FALSE), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  fire_letter_id     :string
#  marked_fire_by_id  :bigint
#
# Indexes
#
#  index_projects_on_deleted_at         (deleted_at)
#  index_projects_on_marked_fire_by_id  (marked_fire_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (marked_fire_by_id => users.id)
#
require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
