# == Schema Information
#
# Table name: email_templates
#
#  id         :bigint           not null, primary key
#  body       :text
#  name       :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_email_templates_on_name  (name) UNIQUE
#
class EmailTemplate < ApplicationRecord
  has_paper_trail

  validates :name, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_-]+\z/, message: "only lowercase letters, numbers, hyphens, underscores" }
  validates :body, presence: true

  def to_param
    name
  end
end
