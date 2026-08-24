require "test_helper"

class RackAttackTest < ActiveSupport::TestCase
  test "uses the authenticated session user as the throttle discriminator" do
    request = Rack::Attack::Request.new(
      Rack::MockRequest.env_for("/", "REMOTE_ADDR" => "192.0.2.1", "rack.session" => { user_id: 123 })
    )

    assert_equal "user:123", RackAttackClient.user_or_ip(request)
  end

  test "uses the request IP as the throttle discriminator for signed-out requests" do
    request = Rack::Attack::Request.new(
      Rack::MockRequest.env_for("/", "REMOTE_ADDR" => "192.0.2.1", "rack.session" => {})
    )

    assert_equal "ip:192.0.2.1", RackAttackClient.user_or_ip(request)
  end

  test "installs Rack Attack once and after the session middleware" do
    middleware = middleware_classes(Rails.application.app)
    rack_attack_index = middleware.index(Rack::Attack)
    session_index = middleware.index(ActionDispatch::Session::CookieStore)

    assert_equal 1, middleware.count(Rack::Attack)
    assert_operator rack_attack_index, :>, session_index
  end

  private

  def middleware_classes(app)
    classes = []

    while app.instance_variable_defined?(:@app)
      classes << app.class
      app = app.instance_variable_get(:@app)
    end

    classes
  end
end
