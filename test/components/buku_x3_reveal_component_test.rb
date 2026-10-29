require "test_helper"

class BukuX3RevealComponentTest < ViewComponent::TestCase
  setup do
    @user = users(:one)
    @user.update!(onboarded_at: Time.current, things_dismissed: [ "bukux3_intro" ])
    Flipper.disable(:bukux2)
    Flipper.disable(:bukux3)
    @event = BukuX3::Event.create!(key: BukuX3::Event::KEY, unlocked_at: 1.minute.ago)
  end

  teardown do
    Flipper.disable(:bukux2)
    Flipper.disable(:bukux3)
  end

  test "flag enables the reveal without a milestone" do
    @event.update!(unlocked_at: nil)
    Flipper.enable(:bukux3)
    BukuX3::Assignment.stub(:buku?, true) do
      render_inline BukuX3RevealComponent.new(user: @user)
    end
    assert_selector ".buku-x3-reveal", visible: :all
  end

  test "renders the one-time reveal for an assigned Buku Buku" do
    Flipper.enable(:bukux3)

    BukuX3::Assignment.stub(:buku?, true) do
      render_inline BukuX3RevealComponent.new(user: @user)
    end

    assert_selector ".buku-x3-reveal[data-controller='buku-x3-reveal']"
    assert_selector ".buku-x3-reveal__title span", text: "you are a"
    assert_selector ".buku-x3-reveal__title em", text: "buku buku"
    assert_selector "img.buku-x3-reveal__badge[src*='events/bukux3/buku']"
    assert_selector "img[src*='events/bukux3/shh']"
    assert_selector ".buku-x3-reveal[data-buku-x3-reveal-animation-url-value*='shh-animated']"
    assert_selector ".buku-x3-reveal__description", normalize_ws: true, exact_text: "your hours will contribute to the destruction of the ship - make sure no stardancer will be able to return home!"
    assert_selector ".buku-x3-reveal[data-buku-x3-reveal-dismiss-thing-value='#{BukuX3RevealComponent::DISMISS_THING}']"
  end

  test "renders the same shushing animation for beans" do
    Flipper.enable(:bukux3)

    BukuX3::Assignment.stub(:buku?, false) do
      render_inline BukuX3RevealComponent.new(user: @user)
    end

    assert_selector ".buku-x3-reveal--bean"
    assert_selector ".buku-x3-reveal__title em", text: "bean"
    assert_selector "img.buku-x3-reveal__badge[src*='events/bukux3/bean']"
    assert_selector "img[src*='events/bukux3/shh']"
    assert_selector ".buku-x3-reveal[data-buku-x3-reveal-animation-url-value*='shh-animated']"
    assert_selector ".buku-x3-reveal__description", normalize_ws: true, exact_text: "your hours will contribute to fixing the rocket that'll take us all home. defeat the buku bukus!"
    assert_no_selector "img[src*='wrench-buddy']"
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

  test "does not choose a role until the buku explanation is completed" do
    Flipper.enable(:bukux3)
    Flipper.enable(:bukux2)
    @user.undismiss_thing!("bukux3_intro")

    BukuX3::Assignment.stub(:buku?, ->(_) { flunk "role chosen before intro completion" }) do
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
      other_user.update!(onboarded_at: Time.current, things_dismissed: [ "bukux3_intro" ])
      render_inline BukuX3RevealComponent.new(user: other_user)
      assert_no_selector ".buku-x3-reveal", visible: :all
    end
  end

  test "a dismissal persists on the account across reloads" do
    @user.dismiss_thing!(BukuX3RevealComponent::DISMISS_THING)

    assert User.find(@user.id).has_dismissed?(BukuX3RevealComponent::DISMISS_THING)
  end
end
