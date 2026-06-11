ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "view_component/test_helpers"

# minitest 6 dropped `Object#stub` (the block-style method stubber the suite
# relies on, e.g. `Foo.stub(:bar, value) { ... }`). Restore the classic
# minitest 5 implementation when it's absent so tests that lean on `.stub` keep
# working without pulling in mocha or rspec-mocks.
unless Object.method_defined?(:stub) || Object.private_method_defined?(:stub)
  class Object
    def stub(name, val_or_callable, *block_args, **block_kwargs, &block)
      new_name = "__minitest_stub__#{name}"
      metaclass = class << self; self; end

      if respond_to?(name) && !methods.map(&:to_s).include?(name.to_s)
        metaclass.send :define_method, name do |*args|
          super(*args)
        end
      end

      metaclass.send :alias_method, new_name, name
      metaclass.send :define_method, name do |*args, **kwargs, &blk|
        if val_or_callable.respond_to?(:call)
          val_or_callable.call(*args, **kwargs, &blk)
        else
          blk.call(*block_args, **block_kwargs) if blk
          val_or_callable
        end
      end

      yield self
    ensure
      metaclass.send :undef_method, name
      metaclass.send :alias_method, name, new_name
      metaclass.send :undef_method, new_name
    end
  end
end

Dir[Rails.root.join("test/support/**/*.rb")].each { |f| require f }

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    include UserFactory
    include MissionFactory
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
