require "test_helper"

# == Schema Information
#
# Table name: certification_review_notes
#
#  id         :bigint           not null, primary key
#  body       :text
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  author_id  :bigint           not null
#  project_id :bigint           not null
#
# Indexes
#
#  index_certification_review_notes_on_author_id   (author_id)
#  index_certification_review_notes_on_project_id  (project_id)
#
# Foreign Keys
#
#  fk_rails_...  (author_id => users.id)
#  fk_rails_...  (project_id => projects.id)
#
class Certification::ReviewNoteTest < ActiveSupport::TestCase
  def setup
    @project = Project.create!(title: "HW #{SecureRandom.hex(4)}", hardware_stage: "design")
    @author = User.create!(
      email: "rev-#{SecureRandom.hex(6)}@example.com",
      display_name: "Rev#{SecureRandom.hex(3)}",
      slack_id: "U#{SecureRandom.hex(8)}"
    )
  end

  test "requires a body" do
    note = Certification::ReviewNote.new(project: @project, author: @author)
    assert_not note.valid?
    assert note.errors[:body].any?
  end

  test "belongs to a project and a user author" do
    note = Certification::ReviewNote.create!(project: @project, author: @author, body: "Looks good.")
    assert_equal @project, note.project
    assert_equal @author, note.author
    assert_instance_of User, note.author
  end

  test "a project has many review notes and destroys them with the project" do
    Certification::ReviewNote.create!(project: @project, author: @author, body: "One")
    Certification::ReviewNote.create!(project: @project, author: @author, body: "Two")
    assert_equal 2, @project.review_notes.count

    assert_difference -> { Certification::ReviewNote.count }, -2 do
      @project.destroy
    end
  end

  test "newest_first orders by created_at descending" do
    older = Certification::ReviewNote.create!(project: @project, author: @author, body: "Older", created_at: 2.days.ago)
    newer = Certification::ReviewNote.create!(project: @project, author: @author, body: "Newer", created_at: 1.hour.ago)
    assert_equal [ newer, older ], @project.review_notes.newest_first.to_a
  end

  test "is versioned by paper_trail" do
    note = Certification::ReviewNote.create!(project: @project, author: @author, body: "Audited")
    assert_respond_to note, :versions
    assert_equal 1, note.versions.count
  end

  test "the fixture loads" do
    assert certification_review_notes(:reviewer_note_one).body.present?
  end
end
