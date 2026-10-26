require "test_helper"

class PromosControllerTest < ActionDispatch::IntegrationTest
  test "the animated mipmap ad counts once without redirecting the tracking request" do
    tracked = []
    original = Ahoy::Store.instance_method(:track_event)
    Ahoy::Store.define_method(:track_event) { |data| tracked << data[:name] }
    begin
      sign_in users(:tongyu)
      get mipmap_promo_path, headers: {
        "Accept" => "application/json",
        "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 Safari/605.1.15"
      }
    ensure
      Ahoy::Store.define_method(:track_event, original)
    end

    assert_response :no_content
    assert_nil response.headers["Location"]
    assert_equal [ DiscoverRail::MipmapPromoWidget::CLICK_EVENT ], tracked
  end

  test "the mipmap ad counts the click and sends the visitor on to mipmap" do
    tracked = []
    original = Ahoy::Store.instance_method(:track_event)
    Ahoy::Store.define_method(:track_event) { |data| tracked << data[:name] }
    begin
      sign_in users(:tongyu)
      get mipmap_promo_path, headers: { "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 Safari/605.1.15" }
    ensure
      Ahoy::Store.define_method(:track_event, original)
    end

    assert_redirected_to DiscoverRail::MipmapPromoWidget::URL
    assert_equal [ DiscoverRail::MipmapPromoWidget::CLICK_EVENT ], tracked
  end

  test "the save point ad counts the click and sends the visitor on to save point" do
    tracked = []
    original = Ahoy::Store.instance_method(:track_event)
    Ahoy::Store.define_method(:track_event) { |data| tracked << data[:name] }
    begin
      sign_in users(:tongyu)
      get savepoint_promo_path, headers: { "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 Safari/605.1.15" }
    ensure
      Ahoy::Store.define_method(:track_event, original)
    end

    assert_redirected_to "https://savepoint.hackclub.com/?utm_source=stardance&utm_medium=discover_rail&utm_campaign=big_type"
    assert_equal [ DiscoverRail::SavepointPromoWidget::CLICK_EVENT ], tracked
  end

  test "the day one of ad counts the click and sends the visitor on to day one of" do
    tracked = []
    original = Ahoy::Store.instance_method(:track_event)
    Ahoy::Store.define_method(:track_event) { |data| tracked << data[:name] }
    begin
      sign_in users(:tongyu)
      get day_one_of_promo_path, headers: { "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 Safari/605.1.15" }
    ensure
      Ahoy::Store.define_method(:track_event, original)
    end

    assert_redirected_to DiscoverRail::DayOneOfPromoWidget::URL
    assert_equal [ DiscoverRail::DayOneOfPromoWidget::CLICK_EVENT ], tracked
  end

  test "the wrong tool ad counts the click and sends the visitor on to wrong tool" do
    tracked = []
    original = Ahoy::Store.instance_method(:track_event)
    Ahoy::Store.define_method(:track_event) { |data| tracked << data[:name] }
    begin
      sign_in users(:tongyu)
      get wrong_tool_promo_path, headers: { "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 Safari/605.1.15" }
    ensure
      Ahoy::Store.define_method(:track_event, original)
    end

    assert_redirected_to Feed::WrongToolPromoComponent::URL
    assert_equal [ Feed::WrongToolPromoComponent::CLICK_EVENT ], tracked
  end
end
