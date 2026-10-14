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
module Certification
  # An internal, reviewer-only note about a project, written for the next
  # reviewer. Append-only and timestamped, it persists across the project's
  # funding and ship reviews so context carries between the two hardware stages.
  # Never shown to the builder.
  class ReviewNote < ApplicationRecord
    self.table_name = "certification_review_notes"

    belongs_to :project
    belongs_to :author, class_name: "User"

    has_paper_trail

    validates :body, presence: true

    scope :newest_first, -> { order(created_at: :desc) }
  end
end
