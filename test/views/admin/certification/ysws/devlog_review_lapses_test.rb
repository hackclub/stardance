require "test_helper"

# Rendering-level guard for lapses shown inside their contributing devlog on the
# YSWS review page. The bucketing rule itself is covered by
# Certification::DevlogLapseBucketerTest; this checks the partial actually
# surfaces a bucketed lapse (and stays quiet when a devlog has none).
class Admin::Certification::Ysws::DevlogReviewLapsesTest < ActionView::TestCase
  POST_DEVLOG_ID = 4242

  def devlog_review
    post_devlog = Post::Devlog.new(id: POST_DEVLOG_ID, duration_seconds: 3600, phase: "build", body: "Built the thing")
    review = Certification::Devlog.new(
      id: 77, post_devlog_id: POST_DEVLOG_ID,
      original_minutes: 60, approved_minutes: 60, status: "pending", justification: ""
    )
    review.post_devlog = post_devlog
    review
  end

  def render_devlog(devlog_lapses:)
    @devlog_commits = { POST_DEVLOG_ID => [] }
    @repo_info = nil
    @review = Certification::Ysws.new(id: 1, project: Project.new(repo_url: "https://github.com/example/repo"))
    @devlog_lapses = devlog_lapses
    render partial: "admin/certification/ysws/devlog_review",
           locals: { devlog_review: devlog_review, frozen: false, sidebar_trigger: false, mac_recommendation: nil }
  end

  test "renders a devlog's bucketed timelapses inside the devlog" do
    lapse = {
      id: "tl1", playbackUrl: "https://videos.example/tl1.mp4",
      thumbnailUrl: "https://videos.example/tl1.jpg", name: "Soldering",
      duration: 120, createdAt: "1", visibility: "PUBLIC"
    }

    render_devlog(devlog_lapses: { POST_DEVLOG_ID => [ lapse ] })

    assert_select ".devlog-recordings-section" do
      assert_select ".recording-gallery__source", text: "Lapse"
      assert_select "video source[src=?]", "https://videos.example/tl1.mp4"
    end
  end

  test "omits the recordings section when the devlog has no lapses" do
    render_devlog(devlog_lapses: { POST_DEVLOG_ID => [] })

    assert_select ".devlog-recordings-section", count: 0
  end
end
