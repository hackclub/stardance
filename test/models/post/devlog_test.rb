# == Schema Information
#
# Table name: post_devlogs
#
#  id                               :bigint           not null, primary key
#  body                             :string
#  comments_count                   :integer          default(0), not null
#  deleted_at                       :datetime
#  duration_seconds                 :integer
#  hackatime_project_names_snapshot :text             is an Array
#  hackatime_projects_key_snapshot  :text
#  hackatime_pulled_at              :datetime
#  likes_count                      :integer          default(0), not null
#  phase                            :string
#  synced_at                        :datetime
#  tutorial                         :boolean          default(FALSE), not null
#  created_at                       :datetime         not null
#  updated_at                       :datetime         not null
#
# Indexes
#
#  index_post_devlogs_on_deleted_at  (deleted_at)
#
require "test_helper"

class Post::DevlogTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  PIXEL_PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")

  test "enqueues one semantic search index job per devlog create and update" do
    devlog = Post::Devlog.new(body: "first pass", duration_seconds: 1.hour)
    devlog.attachments.attach(io: StringIO.new(PIXEL_PNG), filename: "progress.png", content_type: "image/png")

    devlog_index_jobs = -> {
      enqueued_jobs.count { |job| job["job_class"] == "SemanticSearch::IndexRecordJob" && job["arguments"].first == "Post::Devlog" }
    }

    clear_enqueued_jobs
    devlog.save!
    Post.create!(project: projects(:one), user: users(:one), postable: devlog)
    assert_equal 1, devlog_index_jobs.call

    clear_enqueued_jobs
    devlog.update!(body: "second pass")
    assert_equal 1, devlog_index_jobs.call
  end

  test "creates a version through the public version history API" do
    devlog = post_devlogs(:one)

    version = devlog.create_version!(user: users(:one), previous_body: "Original body")

    assert_equal "Original body", version.previous_body
    assert_equal 1, version.version_number
    assert_equal 1, devlog.current_version_number
  end
end
