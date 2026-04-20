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
#  lapse_video_processing          :boolean          default(FALSE), not null
#  likes_count                     :integer          default(0), not null
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
  # test "the truth" do
  #   assert true
  # end
end
