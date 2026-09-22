require "test_helper"

class BukuX3RevealComponentTest < ViewComponent::TestCase
  setup do
    @user = users(:one)
    @user.update!(onboarded_at: Time.current, things_dismissed: [])
    Flipper.disable(:bukux2)
    Flipper.disable(:bukux3)
  end

  teardown do
    Flipper.disable(:bukux2)
    Flipper.disable(:bukux3)
  end

  test "renders the one-time reveal for an assigned Buku Buku" do
    Flipper.enable(:bukux3)

    BukuX3::Assignment.stub(:buku?, true) do
      render_inline BukuX3RevealComponent.new(user: @user)
    end

    assert_selector ".buku-x3-reveal[data-controller='buku-x3-reveal']"
    assert_selector ".buku-x3-reveal__title span", text: "you are a"
    assert_selector ".buku-x3-reveal__title em", text: "buku buku"
    assert_selector "img[src*='events/bukux3/shh']"
    assert_selector ".buku-x3-reveal[data-buku-x3-reveal-dismiss-thing-value='#{BukuX3RevealComponent::DISMISS_THING}']"
  end

  test "renders nothing for the normal half" do
    Flipper.enable(:bukux3)

    BukuX3::Assignment.stub(:buku?, false) do
      render_inline BukuX3RevealComponent.new(user: @user)
    end

    assert_no_selector ".buku-x3-reveal"
  end

  test "renders nothing when the flag is off" do
    Flipper.disable(:bukux3)

    BukuX3::Assignment.stub(:buku?, true) do
      render_inline BukuX3RevealComponent.new(user: @user)
    end

    assert_no_selector ".buku-x3-reveal"
  end

  test "renders nothing after the reveal has been dismissed" do
    Flipper.enable(:bukux3)
    @user.dismiss_thing!(BukuX3RevealComponent::DISMISS_THING)

    BukuX3::Assignment.stub(:buku?, true) do
      render_inline BukuX3RevealComponent.new(user: @user)
    end

    assert_no_selector ".buku-x3-reveal"
  end

  test "does not compete with the existing visual novel" do
    Flipper.enable(:bukux3)
    Flipper.enable(:bukux2)

    BukuX3::Assignment.stub(:buku?, true) do
      render_inline BukuX3RevealComponent.new(user: @user)
    end

    assert_no_selector ".buku-x3-reveal"
  end

  test "renders nothing for a signed-out visitor" do
    Flipper.enable(:bukux3)

    render_inline BukuX3RevealComponent.new(user: nil)

    assert_no_selector ".buku-x3-reveal", visible: :all
  end

  test "waits until onboarding is complete" do
    Flipper.enable(:bukux3)
    @user.update!(onboarded_at: nil)

    BukuX3::Assignment.stub(:buku?, true) do
      render_inline BukuX3RevealComponent.new(user: @user)
    end

    assert_no_selector ".buku-x3-reveal", visible: :all
  end

  test "waits until the welcome tour is finished" do
    Flipper.enable(:bukux3)

    with_request_url "/home?welcome=1" do
      BukuX3::Assignment.stub(:buku?, true) do
        render_inline BukuX3RevealComponent.new(user: @user)
      end
    end

    assert_no_selector ".buku-x3-reveal", visible: :all
  end

  test "honors an actor-specific rollout" do
    Flipper.enable_actor(:bukux3, @user)

    BukuX3::Assignment.stub(:buku?, true) do
      render_inline BukuX3RevealComponent.new(user: @user)
      assert_selector "dialog.buku-x3-reveal", visible: :all

      other_user = users(:two)
      other_user.update!(onboarded_at: Time.current, things_dismissed: [])
      render_inline BukuX3RevealComponent.new(user: other_user)
      assert_no_selector ".buku-x3-reveal", visible: :all
    end
  end

  test "a dismissal persists on the account across reloads" do
    @user.dismiss_thing!(BukuX3RevealComponent::DISMISS_THING)

    assert User.find(@user.id).has_dismissed?(BukuX3RevealComponent::DISMISS_THING)
  end
end
