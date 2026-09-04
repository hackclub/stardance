require "test_helper"

class VisualNovelComponentTest < ViewComponent::TestCase
  setup do
    @user = users(:one)
    @user.update!(onboarded_at: Time.current)
    # The replay switch is a temporary testing affordance; these cover the
    # shipping behaviour, so turn it off for all but the replay test.
    VisualNovelComponent.replay_every_load = false
  end

  teardown do
    VisualNovelComponent.replay_every_load = true
  end

  test "renders the dialogue scene when the flag is on" do
    Flipper.enable(:bukux2)

    render_inline VisualNovelComponent.new(user: @user)

    assert_selector ".visual-novel[data-controller='visual-novel']"
    assert_selector ".visual-novel__speaker", text: VisualNovelComponent::SPEAKER
    assert_selector ".visual-novel__line", text: "hi, #{@user.display_name}!"
    assert_selector ".visual-novel__dot", count: VisualNovelComponent::LINES.size
    assert_selector ".visual-novel[data-visual-novel-dismiss-thing-value='#{VisualNovelComponent::DISMISS_THING}']"
  end

  test "greets an account with no display name without a blank" do
    Flipper.enable(:bukux2)
    # Validated as present, so only rows written around the validation (imports,
    # data predating it) can be blank — which is what the fallback is for.
    @user.update_column(:display_name, nil)

    render_inline VisualNovelComponent.new(user: @user)

    assert_selector ".visual-novel__line", text: "hi, stardancer!"
  end

  test "renders nothing without the flag" do
    Flipper.disable(:bukux2)

    render_inline VisualNovelComponent.new(user: @user)

    assert_no_selector ".visual-novel"
  end

  test "renders nothing once the scene has been dismissed" do
    Flipper.enable(:bukux2)
    @user.dismiss_thing!(VisualNovelComponent::DISMISS_THING)

    render_inline VisualNovelComponent.new(user: @user)

    assert_no_selector ".visual-novel"
  end

  test "renders nothing while the post-onboarding welcome tour is running" do
    Flipper.enable(:bukux2)
    @user.undismiss_thing!("home_intro")

    with_request_url "/?welcome=1" do
      render_inline VisualNovelComponent.new(user: @user)
    end

    assert_no_selector ".visual-novel"
  end

  test "replay mode ignores the dismissal and suppresses the dismissal POST" do
    Flipper.enable(:bukux2)
    @user.dismiss_thing!(VisualNovelComponent::DISMISS_THING)
    VisualNovelComponent.replay_every_load = true

    render_inline VisualNovelComponent.new(user: @user)

    assert_selector ".visual-novel[data-visual-novel-dismiss-thing-value='']"
  end

  test "renders nothing for guests" do
    Flipper.enable(:bukux2)

    render_inline VisualNovelComponent.new(user: nil)

    assert_no_selector ".visual-novel"
  end
end
