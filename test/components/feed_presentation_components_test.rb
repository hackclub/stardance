require "test_helper"
require "base64"

class FeedPresentationComponentsTest < ViewComponent::TestCase
  setup do
    @user = users(:one)
    @project = projects(:one)
    @devlog = create_devlog(body: "Added a tilemap today")
    @post = Post.create!(project: @project, user: @user, postable: @devlog)
  end

  test "composer renders a project-backed devlog form" do
    render_inline Posts::ComposerComponent.new(
      post: Post::Devlog.new,
      current_user: @user,
      projects: [ @project ],
      selected_project: @project
    )

    assert_text "What are you working on?"
    assert_selector "form[action='#{project_devlogs_path(@project)}']"
    assert_link @project.title
  end

  test "home composer (show_record) renders the record-a-timelapse button for a hardware project" do
    hardware = Project.create!(title: "Solder bot", hardware_stage: "build")
    render_inline Posts::ComposerComponent.new(
      post: Post::Devlog.new,
      current_user: @user,
      projects: [ hardware ],
      selected_project: hardware,
      show_record: true
    )

    assert_selector "button.feed-composer__record[aria-label='Record a timelapse']"
  end

  test "project composer (default) omits the record-a-timelapse button" do
    hardware = Project.create!(title: "Solder bot", hardware_stage: "build")
    render_inline Posts::ComposerComponent.new(
      post: Post::Devlog.new,
      current_user: @user,
      projects: [ hardware ],
      selected_project: hardware
    )

    assert_no_selector ".feed-composer__record", visible: :all
  end

  test "composer renders disabled empty state without projects" do
    render_inline Posts::ComposerComponent.new(
      post: Post::Devlog.new,
      current_user: @user,
      projects: [],
      selected_project: nil
    )

    assert_text "Create your first project"
    assert_text "to begin posting"
    assert_selector "a.empty-project-banner[href='#{new_project_path}']"
    assert_no_selector "form"
  end

  test "post card renders body and attachment media" do
    render_inline Posts::CardComponent.new(post: @post, current_user: @user, show_likes: false)

    assert_text "@#{@user.display_name}"
    assert_text @project.title
    assert_text "Added a tilemap today"
    assert_selector ".feed-post-card__image"
  end

  test "post card renders without liked state" do
    render_inline Posts::CardComponent.new(post: @post, current_user: @user)

    assert_selector ".feed-post-card"
    assert_text "0"
    assert_no_selector ".like-button__btn--liked"
  end

  test "post card hides the view count without week_2_release" do
    render_inline Posts::CardComponent.new(post: @post, current_user: @user)

    assert_no_selector "[title='Unique viewers']"
  end

  test "post card shows the unique view count with week_2_release" do
    Flipper.enable(:week_2_release)
    @post.update!(views_count: 3)

    render_inline Posts::CardComponent.new(post: @post, current_user: @user)

    assert_selector "[title='Unique viewers']", text: "3"
  end

  test "shelf renders project cards" do
    # render_inline runs in the component's view context, so render the card to
    # HTML there, then feed it into the shelf slot — the slot block runs in the
    # test's own context, where `render` isn't available.
    card_html = render_inline(Projects::ShelfCardComponent.new(project: @project)).to_html

    render_inline Feed::ShelfComponent.new(title: "Recommended projects", items: [ @project ], href: "/projects") do |shelf|
      shelf.with_item { card_html.html_safe }
    end

    assert_text "Recommended projects"
    assert_link @project.title, href: project_path(@project)
  end

  test "shelf renders nothing with empty collection" do
    render_inline Feed::ShelfComponent.new(title: "Recommended projects", items: [])

    assert_no_selector ".feed-shelf"
  end

  private

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
