require "test_helper"

# Rendering-level guard for recordings shown inside their contributing devlog on
# the YSWS review page. The bucketing rule itself is covered by
# Certification::DevlogRecordingBucketerTest; this checks the partial actually
# surfaces bucketed Lapse and Lookout recordings (and stays quiet when a devlog
# has none).
class Admin::Certification::Ysws::DevlogReviewRecordingsTest < ActionView::TestCase
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

  def render_devlog(devlog_lapses: {}, devlog_lookouts: {})
    @devlog_commits = { POST_DEVLOG_ID => [] }
    @repo_info = nil
    @review = Certification::Ysws.new(id: 1, project: Project.new(repo_url: "https://github.com/example/repo"))
    @devlog_lapses = devlog_lapses
    @devlog_lookouts = devlog_lookouts
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

  test "renders a devlog's bucketed lookout recordings inside the devlog" do
    lookout = {
      video_url: "https://videos.example/lo1.mp4",
      thumbnail_url: "https://videos.example/lo1.jpg",
      mode: "desktop", duration: 90, recorded_at: Time.utc(2026, 6, 1, 12)
    }

    render_devlog(devlog_lookouts: { POST_DEVLOG_ID => [ lookout ] })

    assert_select ".devlog-recordings-section" do
      assert_select ".recording-gallery__source", text: "Lookout"
      assert_select "video source[src=?]", "https://videos.example/lo1.mp4"
      # Telescreen has no Lookout workbench, so a Lookout recording never links out.
      assert_select ".recording-gallery__telescreen", count: 0
    end
  end

  test "omits the recordings section when the devlog has no recordings" do
    render_devlog(devlog_lapses: { POST_DEVLOG_ID => [] }, devlog_lookouts: { POST_DEVLOG_ID => [] })

    assert_select ".devlog-recordings-section", count: 0
  end
end
