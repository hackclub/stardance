# == Schema Information
#
# Table name: projects
#
#  id                   :bigint           not null, primary key
#  ai_declaration       :text
#  deleted_at           :datetime
#  demo_url             :text
#  description          :text
#  devlogs_count        :integer          default(0), not null
#  duration_seconds     :integer          default(0), not null
#  hardware_stage       :string
#  marked_fire_at       :datetime
#  memberships_count    :integer          default(0), not null
#  nominated_fire_at    :datetime
#  project_categories   :string           default([]), is an Array
#  project_type         :string
#  readme_url           :text
#  repo_url             :text
#  ship_status          :string           default("draft")
#  shipped_at           :datetime
#  synced_at            :datetime
#  title                :string           not null
#  tutorial             :boolean          default(FALSE), not null
#  update_description   :text
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  fire_letter_id       :string
#  marked_fire_by_id    :bigint
#  nominated_fire_by_id :bigint
#
# Indexes
#
#  index_projects_on_deleted_at            (deleted_at)
#  index_projects_on_marked_fire_by_id     (marked_fire_by_id)
#  index_projects_on_nominated_fire_by_id  (nominated_fire_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (marked_fire_by_id => users.id)
#  fk_rails_...  (nominated_fire_by_id => users.id)
#
require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  setup do
    Flipper.enable(:hardware_flow)
  end

  test "a valid hardware_stage marks the project as hardware" do
    project = Project.create!(title: "Soldering rig", hardware_stage: "build")

    assert_equal "build", project.hardware_stage
    assert project.hardware?
    assert project.build_stage?
  end

  test "a blank hardware_stage normalizes to nil (software project)" do
    project = Project.create!(title: "Convertible", hardware_stage: "design")
    assert project.hardware?

    # The edit form's type toggle submits "" when Software is selected.
    project.update!(hardware_stage: "")

    assert_nil project.hardware_stage
    assert_not project.hardware?
  end

  test "an invalid hardware_stage is rejected" do
    project = Project.new(title: "Bad stage", hardware_stage: "prototype")

    assert_not project.valid?
    assert project.errors[:hardware_stage].any?
  end
end
