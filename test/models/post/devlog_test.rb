# == Schema Information
#
# Table name: post_devlogs
#
#  id                              :bigint           not null, primary key
#  body                            :string
#  comments_count                  :integer          default(0), not null
#  deleted_at                      :datetime
#  duration_seconds                :integer
#  hackatime_projects_key_snapshot :text
#  hackatime_pulled_at             :datetime
#  likes_count                     :integer          default(0), not null
#  phase                           :string
#  synced_at                       :datetime
#  tutorial                        :boolean          default(FALSE), not null
#  created_at                      :datetime         not null
#  updated_at                      :datetime         not null
#
# Indexes
#
#  index_post_devlogs_on_deleted_at  (deleted_at)
#
require "test_helper"

class Post::DevlogTest < ActiveSupport::TestCase
  test "creates a version through the public version history API" do
    devlog = post_devlogs(:one)

    version = devlog.create_version!(user: users(:one), previous_body: "Original body")

    assert_equal "Original body", version.previous_body
    assert_equal 1, version.version_number
    assert_equal 1, devlog.current_version_number
  end
end
