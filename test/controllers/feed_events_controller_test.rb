require "test_helper"
require "base64"

class FeedEventsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @user.update!(verification_status: "verified")
    @project = projects(:one)
    @project.update!(title: "Tracked Project", description: "Something real", devlogs_count: 1)
    @devlog = create_devlog(body: "Reading telemetry test body")
    @post = Post.create!(project: @project, user: @user, postable: @devlog)
    sign_in @user
  end

  test "records read feedback for visible feed posts" do
    with_gorse_enabled do
      assert_enqueued_with(job: Gorse::SyncFeedbackJob) do
        post feed_events_path, params: {
          events: [
            {
              event_type: "read",
              item_type: "post",
              post_id: @post.id,
              project_id: @project.id,
              source: "quality_latest",
              visible_ms: 8_100,
              visibility_ratio: 0.8
            }
          ]
        }, as: :json
      end
    end

    assert_response :accepted
  end

  test "does not enqueue duplicate read events in same window" do
    with_gorse_enabled do
      with_memory_cache do
        assert_enqueued_jobs 1, only: Gorse::SyncFeedbackJob do
          2.times do
            post feed_events_path, params: {
              events: [
                {
                  event_type: "read",
                  item_type: "post",
                  post_id: @post.id,
                  feed_request_id: "same-feed"
                }
              ]
            }, as: :json
          end
        end
      end
    end
  end

  test "impressions stay out of Gorse" do
    with_gorse_enabled do
      assert_no_enqueued_jobs only: Gorse::SyncFeedbackJob do
        post feed_events_path, params: {
          events: [
            {
              event_type: "impression",
              item_type: "post",
              post_id: @post.id
            }
          ]
        }, as: :json
      end
    end

    assert_response :accepted
  end

  test "impression records a unique post view across feed requests" do
    assert_difference -> { PostView.count } => 1, -> { @post.reload.views_count } => 1 do
      2.times do |i|
        post feed_events_path, params: {
          events: [
            {
              event_type: "impression",
              item_type: "post",
              post_id: @post.id,
              feed_request_id: "feed-#{i}"
            }
          ]
        }, as: :json
      end
    end

    assert_nil PostView.find_by!(post: @post, user: @user).read_at
  end

  test "impression on a repost credits the original post too" do
    reposter = users(:two)
    reposter.update!(verification_status: "verified")
    repost = Post::Repost.create!(original_post: @post, user: reposter)
    repost_post = Post.create!(user: reposter, postable: repost)

    assert_difference -> { @post.reload.views_count } => 1, -> { repost_post.reload.views_count } => 1 do
      post feed_events_path, params: {
        events: [
          {
            event_type: "impression",
            item_type: "post",
            post_id: repost_post.id
          }
        ]
      }, as: :json
    end
  end

  test "read stamps read_at on the post view" do
    post feed_events_path, params: {
      events: [
        {
          event_type: "read",
          item_type: "post",
          post_id: @post.id
        }
      ]
    }, as: :json

    assert_predicate PostView.find_by!(post: @post, user: @user).read_at, :present?
    assert_equal 1, @post.reload.views_count
  end

  private
    def with_gorse_enabled
      original = Gorse.method(:enabled?)
      Gorse.define_singleton_method(:enabled?) { true }
      yield
    ensure
      Gorse.define_singleton_method(:enabled?, &original)
    end

    def with_memory_cache
      original_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      yield
    ensure
      Rails.cache = original_cache
    end

    def create_devlog(body:)
      devlog = Post::Devlog.new(body: body, duration_seconds: 1.hour)
      devlog.attachments.attach(
        io: StringIO.new(Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")),
        filename: "progress.png",
        content_type: "image/png"
      )
      devlog.save!
      devlog
    end
end
