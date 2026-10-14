require "test_helper"

# The "Open in Telescreen" link on Lapse recordings in the shared recordings
# gallery. The URL itself is covered by TelescreenHelperTest; this checks the
# gallery surfaces the link for a Lapse (given the owner uid) and never for a
# Lookout recording or when the uid is missing.
class Admin::Certification::FundingRequests::RecordingsTelescreenTest < ActionView::TestCase
  LAPSE = {
    id: "lapse-1", playbackUrl: "https://videos.example/l1.mp4",
    thumbnailUrl: "", name: "Soldering", duration: 120, createdAt: "1", visibility: "PUBLIC"
  }.freeze
  LOOKOUT = { video_url: "https://videos.example/lk.mp4", thumbnail_url: "", mode: "screen", duration: 60, recorded_at: nil }.freeze

  def render_recordings(timelapses:, recordings: [], telescreen_uid: nil)
    render partial: "admin/certification/funding_requests/recordings",
           locals: { timelapses: timelapses, recordings: recordings, telescreen_uid: telescreen_uid }
  end

  test "shows an Open in Telescreen link on a Lapse when the owner uid is present" do
    render_recordings(timelapses: [ LAPSE ], telescreen_uid: "51046")

    assert_select "a.recording-gallery__telescreen[href=?]",
                  "https://telescreen.hackclub.com/workbench/lapse?u=51046&t=lapse-1"
  end

  test "omits the Telescreen link when the owner uid is missing" do
    render_recordings(timelapses: [ LAPSE ], telescreen_uid: nil)

    assert_select "a.recording-gallery__telescreen", count: 0
  end

  test "never shows a Telescreen link on a Lookout recording" do
    render_recordings(timelapses: [], recordings: [ LOOKOUT ], telescreen_uid: "51046")

    assert_select "a.recording-gallery__telescreen", count: 0
  end
end
