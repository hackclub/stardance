ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "view_component/test_helpers"

Dir[Rails.root.join("test/support/**/*.rb")].each { |f| require f }

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    include UserFactory
  end
end

class ViewComponent::TestCase
  include Rails.application.routes.url_helpers
  include ViewComponent::TestHelpers

  def test_error_path
    assert true
  end

  def test_error_url
    assert true
  end
end

module ActionDispatch
  class IntegrationTest
    private

    def sign_in(user)
      get dev_login_path(user.id)
    end
  end
end
