require "test_helper"

class UsersProfileActivityTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user(slack_id: "U_PA_ADMIN", display_name: "pa_admin", verified: true)
    @admin.grant_role!(:admin)
    @owner = create_user(slack_id: "U_PA_OWNER", display_name: "pa_owner", verified: true)

    @project = Project.create!(title: "Starry Project", marked_fire_at: Time.current, marked_fire_by: @admin)
    @project.memberships.create!(user: @owner, role: :owner)
    Post.create!(project: @project, user: @admin, postable: Post::FireEvent.create!)
  end

  test "super star post is not shown on the granting admin's profile" do
    sign_in @admin

    get user_path(@admin)

    assert_response :success
    assert_select ".feed-post-card--fire", 0
  end

  test "project mission badges load without a query per project" do
    add_mission_project = lambda do |i|
      mission = Mission.create!(slug: "badge-#{i}", name: "Badge #{i}", description: "Mission #{i}")
      mission.icon.attach(io: StringIO.new(Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")), filename: "icon.png", content_type: "image/png")
      project = Project.create!(title: "Mission project #{i}")
      project.memberships.create!(user: @owner, role: :owner)
      project.mission_attachments.create!(mission: mission, attached_at: Time.current)
    end
    # `WHERE id = $1`-style lookups per table, the shape a per-project N+1 takes.
    single_row_lookups = lambda do
      counts = Hash.new(0)
      callback = lambda do |*, payload|
        table = payload[:sql][/\ASELECT .* FROM "(\w+)" WHERE "\1"\."\w+" = \$1/, 1]
        counts[table] += 1 if table
      end
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get user_path(@owner, tab: "projects") }
      counts
    end

    1.upto(2) { |i| add_mission_project.call(i) }
    get user_path(@owner, tab: "projects")
    few = single_row_lookups.call

    3.upto(4) { |i| add_mission_project.call(i) }
    many = single_row_lookups.call

    assert_response :success
    assert_select ".profile-project-card__mission-badge-icon", 4
    assert_equal few, many
  end

  test "super star post is still shown on the project" do
    sign_in @admin

    get project_path(@project)

    assert_response :success
    assert_select ".feed-post-card--fire", 1
  end

  test "like buttons read one precomputed set, reposted devlogs included" do
    viewer = create_user(slack_id: "U_PA_VIEWER", display_name: "pa_viewer", verified: true)
    liked = 2.times.map { |i| Post.create!(project: @project, user: @owner, postable: build_devlog("Liked #{i}")) }
    Post.create!(project: @project, user: @owner, postable: build_devlog("Not liked"))

    author = create_user(slack_id: "U_PA_AUTHOR", display_name: "pa_author", verified: true)
    other_project = Project.create!(title: "Other Project")
    other_project.memberships.create!(user: author, role: :owner)
    original = Post.create!(project: other_project, user: author, postable: build_devlog("Reposted"))
    Post.create!(user: @owner, postable: Post::Repost.create!(original_post: original, user: @owner))

    [ *liked, original ].each { |post| Like.create!(user: viewer, likeable: post.postable) }
    sign_in viewer

    assert_queries_match(/SELECT 1 AS one FROM "likes"/, count: 0) do
      get user_path(@owner)
    end

    assert_response :success
    assert_select ".like-button__btn--liked", 3
    assert_select ".like-button__btn:not(.like-button__btn--liked)", 1
  end

  private
    def build_devlog(body)
      devlog = Post::Devlog.new(body: body, duration_seconds: 1.hour)
      devlog.uploading_attachments = true
      devlog.save!
      devlog
    end
end
