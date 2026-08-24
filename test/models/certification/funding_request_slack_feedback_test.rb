require "test_helper"

# The verdict channel post ("brand new review!!") carries the reviewer's attached
# feedback photos as Slack image blocks. These pin
# Certification::FundingRequest#feedback_image_slack_urls and the image rendering
# in notifications/hardware/review_decided_channel.
class FundingRequestSlackFeedbackTest < ActiveSupport::TestCase
  # 1x1 PNG so attaching produces a real, identifiable image blob.
  PIXEL_PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")

  setup do
    Flipper.enable(:hardware_flow)
    @owner = User.create!(
      email: "owner-#{SecureRandom.hex(6)}@example.com",
      display_name: "Owner#{SecureRandom.hex(3)}",
      slack_id: "U#{SecureRandom.hex(8)}",
      verification_status: :verified, ysws_eligible: true
    )
    @reviewer = User.create!(
      email: "rev-#{SecureRandom.hex(6)}@example.com",
      display_name: "Rev#{SecureRandom.hex(3)}",
      slack_id: "U#{SecureRandom.hex(8)}"
    )
    @project = Project.create!(title: "HW #{SecureRandom.hex(4)}", hardware_stage: "design")
    Project::Membership.create!(project: @project, user: @owner, role: :owner)
    devlog = Post::Devlog.new(body: "initial log", duration_seconds: 3600, phase: "design")
    devlog.uploading_attachments = true
    devlog.save!
    Post.create!(project: @project, user: @owner, postable: devlog)
    @request = @project.certification_funding_requests.create!(
      user: @owner, complexity_tier: 2, requested_amount_cents: 5_000, status: :pending
    )
  end

  def attach_image(name)
    @request.feedback_images.attach(io: StringIO.new(PIXEL_PNG), filename: name, content_type: "image/png")
  end

  test "returns one absolute publicly fetchable url per attached photo" do
    attach_image("a.png")
    attach_image("b.png")

    urls = @request.feedback_image_slack_urls

    assert_equal 2, urls.size
    urls.each do |url|
      assert_match %r{\Ahttps://stardance\.hackclub\.com/rails/active_storage/}, url,
        "Slack fetches the image over the internet, so the url must be absolute + public"
    end
  end

  test "feedback_image_slack_urls is empty when no photos are attached" do
    assert_empty @request.feedback_image_slack_urls
  end

  test "a build review has no feedback image urls" do
    # Ship shares the Reviewable concern but carries no feedback_images
    # association, so the helper must degrade to [] rather than raise.
    assert_empty Certification::Ship.new.feedback_image_slack_urls
  end

  test "the verdict channel post renders one image block per photo" do
    attach_image("a.png")
    attach_image("b.png")

    images = channel_blocks(@request.feedback_image_slack_urls).select { |b| b["type"] == "image" }

    assert_equal 2, images.size
    assert(images.all? { |block| block["image_url"].present? }, "each image block needs an image_url")
  end

  test "the verdict channel post has no image blocks when there are no photos" do
    images = channel_blocks([]).select { |b| b["type"] == "image" }
    assert_empty images
  end

  private

  # Render the review_decided_channel slocks template the way SendSlackDmJob does
  # and return its Slack blocks.
  def channel_blocks(feedback_image_urls)
    rendered = ApplicationController.renderer.new.render(
      template: "notifications/hardware/review_decided_channel",
      formats: [ :slack_message ],
      locals: {
        project_title: @project.title,
        project_url: "https://stardance.hackclub.com/projects/#{@project.id}",
        approved: false,
        reviewer_name: @reviewer.display_name,
        feedback: "Nice work",
        review_type: "design",
        owner_slack_id: @owner.slack_id,
        reviewer_slack_id: @reviewer.slack_id,
        feedback_image_urls: feedback_image_urls
      }
    )
    parsed = JSON.parse(rendered)
    parsed["blocks"] || parsed.values.find { |value| value.is_a?(Array) } || []
  end
end
