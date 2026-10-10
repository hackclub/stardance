require "test_helper"

class PromosControllerTest < ActionDispatch::IntegrationTest
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
