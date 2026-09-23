require "test_helper"

class BukuX3IntroComponentTest < ViewComponent::TestCase
  setup do
    @user = users(:one)
    @user.update!(onboarded_at: Time.current, things_dismissed: [])
    @event = BukuX3::Event.create!(key: BukuX3::Event::KEY, unlocked_at: 1.minute.ago)
    Flipper.enable(:bukux3)
    Flipper.disable(:bukux2)
  end

  teardown do
    Flipper.disable(:bukux3)
    Flipper.disable(:bukux2)
  end

  test "explains the teams before choosing a role" do
    BukuX3::Assignment.stub(:buku?, ->(_) { flunk "intro must not choose a role" }) do
      render_inline VisualNovelComponent.new(user: @user, chapter: :bukux3)
    end
    assert_selector ".visual-novel__speaker", text: "■■■"
    assert_selector ".visual-novel__line", exact_text: "THE ROCKET SHIP IS COMPLETE! finally!"
    assert_selector ".visual-novel__dot", count: 9
    scene = page.find(".visual-novel")
    lines = JSON.parse(scene["data-visual-novel-lines-value"])
    assert_equal [ 1, 6 ], JSON.parse(scene["data-visual-novel-shake-lines-value"])
    assert_equal [ 1, 6 ], lines.each_index.select { |index| lines[index] == "!!!" }
    assert_equal "...or tear it apart so we'll keep stardancing forever...!", lines[7]
    assert_equal "will you be a bean or a buku buku?", lines.last
    assert_selector ".visual-novel[data-visual-novel-dismiss-thing-value='bukux3_intro']"
    assert_selector ".visual-novel[data-visual-novel-next-scene-url-value='#{buku_x3_reveal_path}']"
    assert_no_selector ".buku-x3-reveal", visible: :all
  end

  test "flag starts the intro without the old milestone" do
    @event.update!(unlocked_at: nil)
    render_inline VisualNovelComponent.new(user: @user, chapter: :bukux3)
    assert_selector ".visual-novel"
  end

  test "only plays once per account" do
    @user.dismiss_thing!("bukux3_intro")
    render_inline VisualNovelComponent.new(user: @user, chapter: :bukux3)
    assert_no_selector ".visual-novel"
  end

  test "new chapter supersedes the old repair intro after the goal" do
    Flipper.enable(:bukux2)
    render_inline VisualNovelComponent.new(user: @user)
    assert_no_selector ".visual-novel"
    render_inline VisualNovelComponent.new(user: @user, chapter: :bukux3)
    assert_selector ".visual-novel"
  end

  test "waits for onboarding and welcome tour" do
    @user.update!(onboarded_at: nil)
    render_inline VisualNovelComponent.new(user: @user, chapter: :bukux3)
    assert_no_selector ".visual-novel"
    @user.update!(onboarded_at: Time.current)
    with_request_url "/home?welcome=1" do
      render_inline VisualNovelComponent.new(user: @user, chapter: :bukux3)
    end
    assert_no_selector ".visual-novel"
  end

  test "flag off and signed out visitors do not see the chapter" do
    Flipper.disable(:bukux3)
    render_inline VisualNovelComponent.new(user: @user, chapter: :bukux3)
    assert_no_selector ".visual-novel"
    Flipper.enable(:bukux3)
    render_inline VisualNovelComponent.new(user: nil, chapter: :bukux3)
    assert_no_selector ".visual-novel"
  end
end
