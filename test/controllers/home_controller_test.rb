require "test_helper"
require "base64"

class HomeControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(verification_status: :verified, ysws_eligible: true)
    @project = projects(:one)
    @other_project = projects(:two)
    @project.update!(title: "Current user project")
    @other_project.update!(title: "Recommended project")
    @devlog = create_devlog(body: "Home feed update")
    @post = Post.create!(project: @other_project, user: users(:two), postable: @devlog)
  end

  test "home page loads the shell and lazy feed frame for signed in user" do
    sign_in @user

    get home_path

    assert_response :success
    assert_select ".feed-composer"
    assert_select "turbo-frame#home_feed[src=?]", home_feed_path
  end

  teardown { Flipper.disable(Finality::RAFFLE_FEATURE_FLAG) }

  test "raffle promo is hidden when its flag is disabled" do
    Flipper.disable(Finality::RAFFLE_FEATURE_FLAG)
    get home_path

    assert_response :success
    assert_select ".finality-promo", count: 0
  end

  test "enabled raffle promo sits below the fight and links to the dedicated page" do
    Flipper.enable(Finality::RAFFLE_FEATURE_FLAG)
    travel_to Finality.window.begin do
      get home_path
    end

    assert_response :success
    assert_select "turbo-frame#buku_x3_home_status + a.finality-promo[href=?]", finality_raffle_path
    assert_select ".finality-promo img", count: 2
    assert_select ".finality-raffle-page", count: 0
  end

  test "composer chips read hackatime keys from preloaded rows instead of one query per project" do
    linked = 3.times.map do |i|
      project = Project.create!(title: "Linked project #{i}")
      project.memberships.create!(user: @user, role: :owner)
      User::HackatimeProject.create!(user: @user, project: project, name: "linked-#{i}")
      project
    end
    sign_in @user

    assert_queries_match(/SELECT DISTINCT "user_hackatime_projects"\."name"/, count: 0) do
      get home_path
    end

    assert_response :success
    linked.each do |project|
      assert_select ".feed-composer__chip[data-composer-hackatime-linked-param='true']", text: project.title
    end
    assert_select ".feed-composer__chip[data-composer-hackatime-linked-param='false']", text: @project.title
  end

  test "the ended GPU raffle no longer appears in the home rail, even for participants" do
    @user.raffle_participant || Raffle::Participant.find_or_enroll!(@user)
    sign_in @user

    get home_path

    assert_response :success
    assert_select ".raffle-widget", count: 0
    assert_select "a", text: /GPU Raffle/, count: 0
  end

  test "for you candidate selection keeps authors and projects diverse" do
    posts = [
      Post.new(id: 1, user_id: 1, project_id: 1, postable_type: "Post::Devlog"),
      Post.new(id: 2, user_id: 1, project_id: 2, postable_type: "Post::Devlog"),
      Post.new(id: 3, user_id: 2, project_id: 1, postable_type: "Post::Devlog"),
      Post.new(id: 4, user_id: 2, project_id: 2, postable_type: "Post::Devlog"),
      Post.new(id: 5, user_id: 3, project_id: 3, postable_type: "Post::Devlog")
    ]
    candidates = posts.map { |post| [ post, "recommended" ] }

    selected, = Home::FeedsController.new.send(:select_diverse_candidates, candidates, limit: 3)

    assert_equal [ 1, 4, 5 ], selected.map(&:id)
  end

  test "guests see team progress without a role hover or legacy rocket bar" do
    Flipper.enable(:bukux2)
    BukuX3::Assignment.stub(:buku?, ->(_) { flunk "guest must not receive a role" }) do
      get home_path
    end
    assert_response :success
    assert_select ".buku-x3-status [role='meter']", count: 1
    assert_select ".buku-x3-status__toggle, .buku-x3-status__identity, .rocket-progress", count: 0
  ensure
    Flipper.disable(:bukux2)
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
