require "test_helper"

class PromosControllerTest < ActionDispatch::IntegrationTest
  test "the crescent ad counts the click and sends the visitor on to crescent" do
    tracked = []
    original = Ahoy::Store.instance_method(:track_event)
    Ahoy::Store.define_method(:track_event) { |data| tracked << data[:name] }
    begin
      sign_in users(:tongyu)
      get crescent_promo_path, headers: { "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 Safari/605.1.15" }
    ensure
      Ahoy::Store.define_method(:track_event, original)
    end

    assert_redirected_to DiscoverRail::CrescentPromoWidget::URL
    assert_equal [ DiscoverRail::CrescentPromoWidget::CLICK_EVENT ], tracked
  end
end
