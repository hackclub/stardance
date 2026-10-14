require "test_helper"
require "base64"

class GorseRecommendationsTest < ActiveSupport::TestCase
  setup do
    @viewer = users(:one)
    @author = users(:two)
    @viewer.update!(verification_status: :verified, ysws_eligible: true)
    @author.update!(verification_status: :verified, ysws_eligible: true, banned: false)

    @project = projects(:two)
    @project.update!(deleted_at: nil, description: "A visible project")

    @recent_post = create_post("A recent update", 2.hours.ago)
    @old_post = create_post("An old update", 7.hours.ago)
  end

  test "post recommendations exclude posts older than six hours" do
    recommendations = Gorse::Recommendations.new(user: @viewer)
    ids = [ Gorse::Ids.post(@old_post), Gorse::Ids.post(@recent_post) ]

    posts = recommendations.send(:posts_from_ids, ids)

    assert_equal [ @recent_post.id ], posts.map(&:id)
  end

  test "recommendable feed scope includes the boundary window only" do
    ids = Gorse::PostPayload.recommendable_feed_scope(@viewer).where(id: [ @old_post.id, @recent_post.id ]).pluck(:id)

    assert_includes ids, @recent_post.id
    assert_not_includes ids, @old_post.id
  end

  test "post recommendations include at most one post per user and project" do
    posts = [
      Post.new(id: 1, user_id: 1, project_id: 1),
      Post.new(id: 2, user_id: 1, project_id: 2),
      Post.new(id: 3, user_id: 2, project_id: 1),
      Post.new(id: 4, user_id: 2, project_id: 2),
      Post.new(id: 5, user_id: 3, project_id: 3)
    ]

    recommendations = Gorse::Recommendations.new(user: @viewer)
    selected = recommendations.send(:diversify_posts, posts, limit: 3)

    assert_equal [ 1, 4, 5 ], selected.map(&:id)
    assert_equal selected.size, selected.map(&:user_id).uniq.size
    assert_equal selected.size, selected.map(&:project_id).uniq.size
  end

  private
    def create_post(body, created_at)
      devlog = Post::Devlog.new(body: body, duration_seconds: 1.hour)
      devlog.attachments.attach(
        io: StringIO.new(Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")),
        filename: "progress.png",
        content_type: "image/png"
      )
      devlog.save!

      Post.create!(
        project: @project,
        user: @author,
        postable: devlog,
        created_at: created_at,
        updated_at: created_at
      )
    end
end
