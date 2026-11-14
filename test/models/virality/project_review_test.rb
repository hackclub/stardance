require "test_helper"

module Virality
  class ProjectReviewTest < ActiveSupport::TestCase
    setup do
      @project = projects(:two)
      @project.update!(ship_status: "approved", demo_url: "https://orbit-tabs.example.com")
    end

    test "repeat submissions of one link share a key" do
      key = ProjectReview.link_key("https://www.reddit.com/r/SideProject/comments/abc/post/")
      assert_equal key, ProjectReview.link_key("https://reddit.com/r/SideProject/comments/abc/post")
      assert_equal key, ProjectReview.link_key("https://m.reddit.com/r/sideproject/comments/abc/post")

      video = ProjectReview.link_key("https://www.youtube.com/watch?v=q3Xh7RkVb2c&t=10")
      assert_equal "youtube:q3Xh7RkVb2c", video
      assert_equal video, ProjectReview.link_key("https://youtu.be/q3Xh7RkVb2c")
      assert_equal "youtube:abc123", ProjectReview.link_key("https://youtube.com/shorts/abc123")
      refute_equal key, ProjectReview.link_key("https://reddit.com/r/SideProject/comments/xyz/post")

      post = ProjectReview.link_key("https://news.ycombinator.com/item?id=111")
      refute_equal post, ProjectReview.link_key("https://news.ycombinator.com/item?id=222")
      assert_equal post, ProjectReview.link_key("https://news.ycombinator.com/item?id=111&utm_source=x")
      assert_equal ProjectReview.link_key("https://x.com/a/status/1"), ProjectReview.link_key("https://x.com/a/status/1?s=20&t=abc")
    end

    test "warns about links that rarely qualify" do
      assert_equal "Links to the project itself, not a post about it", ProjectReview.warning_for("https://orbit-tabs.example.com/about", @project)
      assert_equal "Links to the project itself, not a post about it", ProjectReview.warning_for("https://someone.github.io/tabs", @project)
      assert_equal "Hack Club platform, doesn't count", ProjectReview.warning_for("https://stardance.hackclub.com/projects/1", @project)
      assert_equal "Localhost link, nobody else can open it", ProjectReview.warning_for("http://localhost:3000", @project)
      assert_equal "Not a listed platform", ProjectReview.warning_for("https://dev.to/someone/post", @project)
      assert_equal "Not a valid link", ProjectReview.warning_for("not a url", @project)
      assert_nil ProjectReview.warning_for("https://news.ycombinator.com/item?id=1", @project)
    end

    test "groups repeats and flags what predicts a rejection" do
      first = @project.mentions.create!(url: "https://www.reddit.com/r/a/comments/1/post", submitter_notes: "front page")
      @project.mentions.create!(url: "https://reddit.com/r/a/comments/1/post/")
      @project.mentions.create!(url: "https://orbit-tabs.example.com", submitter_notes: "my site")
      review = ProjectReview.new(@project, @project.mentions.to_a, scheduled_ids: Set.new)

      repeated = review.groups.find { |group| group.mentions.include?(first) }
      assert_equal 2, repeated.mentions.size
      messages = review.flags.map(&:last)
      assert_includes messages, "1 repeat submission of the same link"
      assert_includes messages, "1 open link unlikely to qualify"
      assert_operator review.red_flags, :>=, 2
    end

    test "states separate held, imported and scheduled mentions from open ones" do
      held = @project.mentions.create!(url: "https://github.com/a/b", on_hold_at: Time.current)
      imported = @project.mentions.create!(url: "https://github.com/a/c", proposed_action: "reject")
      scheduled = @project.mentions.create!(url: "https://github.com/a/d")
      review = ProjectReview.new(@project, [ held, imported, scheduled ], scheduled_ids: Set[scheduled.id])

      assert_equal %w[on_hold awaiting_confirmation scheduled], [ held, imported, scheduled ].map { |mention| review.state_of(mention) }
      assert review.editable?(held)
      refute review.editable?(scheduled)
    end
  end
end
