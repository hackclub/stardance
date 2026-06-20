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
require 'rails_helper'

RSpec.describe EmailTemplate, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
