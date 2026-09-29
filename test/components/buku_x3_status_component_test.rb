require "test_helper"

class BukuX3StatusComponentTest < ViewComponent::TestCase
  setup do
    @user = users(:one)
    @user.update!(onboarded_at: Time.current, things_dismissed: %w[bukux3_intro bukux3_role_reveal])
    @event = BukuX3::Event.create!(key: BukuX3::Event::KEY, unlocked_at: 1.minute.ago, destruction_minutes: 75_000)
    Flipper.enable(:bukux3)
  end

  teardown { Flipper.disable(:bukux3) }

  test "damage moves the marker left and repair moves it right" do
    @event.update!(destruction_minutes: 75 * BukuX3::Event::MINUTES_PER_PERCENT)
    render_inline BukuX3StatusComponent.new(user: @user)
    assert_selector "[role='meter'][aria-valuenow='75.0'][style='--tug-position: 25.0%']"
    @event.update!(destruction_minutes: 25 * BukuX3::Event::MINUTES_PER_PERCENT)
    render_inline BukuX3StatusComponent.new(user: @user)
    assert_selector "[role='meter'][aria-valuenow='25.0'][style='--tug-position: 75.0%']"
  end

  test "uncaptured event starts toward the beans" do
    @event.update!(unlocked_at: nil)
    render_inline BukuX3StatusComponent.new(user: @user)
    assert_selector "[role='meter'][aria-valuenow='25'][style='--tug-position: 75%']"
  end

  test "buku has a role reveal layered over the meter" do
    BukuX3::Assignment.stub(:buku?, true) do
      render_inline BukuX3StatusComponent.new(user: @user)
    end
    assert_selector ".buku-x3-status__role", text: "you're a buku buku"
    assert_selector "button.buku-x3-status__toggle[aria-label='show your event role'][aria-pressed='false']"
    assert_selector "img[src*='events/bukux3/buku']"
    assert_selector ".buku-x3-status__reminder", exact_text: "your objective is to destroy the ship - every hour you code contributes to the downfall of the beans and tears stardance apart"
    assert_selector "[role='meter'][aria-valuenow='25.0'][aria-valuemax='100'][style='--tug-position: 75.0%']"
    assert_selector ".buku-x3-status__team--buku img[src*='bukux3/buku-pulling'][width='2752'][height='2064']"
    assert_selector ".buku-x3-status__team--bean img[src*='bukux3/bean-pulling'][width='2752'][height='2064']"
    assert_selector ".buku-x3-status__label", exact_text: "25% damaged"
    assert_selector ".buku-x3-status__team--buku > span", exact_text: "bukus"
    assert_selector ".buku-x3-status__team--bean > span", exact_text: "beans"
    assert_no_selector ".buku-x3-status__private, .buku-x3-status__directions, .buku-x3-status__balance"
  end

  test "bean sees their yellow badge and repair reminder" do
    BukuX3::Assignment.stub(:buku?, false) do
      render_inline BukuX3StatusComponent.new(user: @user)
    end
    assert_selector ".buku-x3-status__role", text: "you're a bean"
    assert_selector "img[src*='events/bukux3/bean']"
    assert_selector ".buku-x3-status__reminder", exact_text: "your hours will repair the spaceship"
  end

  test "ship reminder is compact and has no duplicate damage meter" do
    render_inline BukuX3StatusComponent.new(user: @user, compact: true)
    assert_selector ".buku-x3-status--compact"
    assert_no_selector "[role='meter']"
    assert_no_selector ".buku-x3-status__hours"
    assert_no_selector ".buku-x3-status__toggle"
  end

  test "each team has its own formatted shipped hours below its name" do
    BukuX3::Event.stub(:current, @event) do
      @event.stub(:team_hours, { buku: 1234.5, bean: 67 }) do
        render_inline BukuX3StatusComponent.new(user: @user)
      end
    end
    assert_selector ".buku-x3-status__team--buku .buku-x3-status__hours", exact_text: "1,234.5 h shipped"
    assert_selector ".buku-x3-status__team--bean .buku-x3-status__hours", exact_text: "67 h shipped"
  end

  test "role is never computed before intro and reveal completion" do
    %w[bukux3_intro bukux3_role_reveal].each do |pending|
      @user.update!(things_dismissed: %w[bukux3_intro bukux3_role_reveal] - [ pending ])
      BukuX3::Assignment.stub(:buku?, ->(_) { flunk "premature role disclosure" }) do
        render_inline BukuX3StatusComponent.new(user: @user)
      end
      assert_no_selector ".buku-x3-status"
    end
  end

  test "badge needs only the flag and completed reveal, not the old milestone" do
    @event.update!(unlocked_at: nil)
    render_inline BukuX3StatusComponent.new(user: @user)
    assert_selector ".buku-x3-status"
    @event.update!(unlocked_at: 1.minute.ago)
    Flipper.disable(:bukux3)
    render_inline BukuX3StatusComponent.new(user: @user)
    assert_no_selector ".buku-x3-status"
  end

  test "signed out and incomplete accounts cannot see a role" do
    render_inline BukuX3StatusComponent.new(user: nil)
    assert_no_selector ".buku-x3-status"
    @user.update!(onboarded_at: nil)
    render_inline BukuX3StatusComponent.new(user: @user)
    assert_no_selector ".buku-x3-status"
  end

  test "panel preview cannot bypass gates outside development" do
    render_inline BukuX3StatusComponent.new(user: nil, preview: true, preview_role: "bean")
    assert_no_selector ".buku-x3-status"
  end

  test "development preview uses an explicit role without assigning an account" do
    Rails.stub(:env, ActiveSupport::StringInquirer.new("development")) do
      BukuX3::Assignment.stub(:buku?, ->(_) { flunk "preview must not assign a role" }) do
        render_inline BukuX3StatusComponent.new(user: nil, preview: true, preview_role: "bean")
      end
    end
    assert_selector ".buku-x3-status__role", text: "you're a bean"
    assert_no_selector ".buku-x3-status__preview"
    assert_selector "img[src*='events/bukux3/bean']"
  end
end
