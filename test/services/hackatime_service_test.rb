require "test_helper"

class HackatimeServiceTest < ActiveSupport::TestCase
  # Regression guard for the duplicate-definition bug: a second `fetch_api_key`
  # under `private` once shadowed the public one, so the heartbeat forwarder's
  # `HackatimeService.fetch_api_key(token)` raised
  # `NoMethodError (private method 'fetch_api_key')` and no seeded project ever
  # reached Hackatime. respond_to? is false for private methods, so this fails
  # the moment the public definition is shadowed again.
  test "fetch_api_key is public and callable with an explicit receiver" do
    assert_respond_to HackatimeService, :fetch_api_key,
      "HackatimeService.fetch_api_key must stay public: Project::EnsureHackatimeProjectsJob calls it with an explicit receiver"
  end

  test "fetch_api_key short-circuits to nil for a blank token without hitting the network" do
    assert_nil HackatimeService.fetch_api_key("")
    assert_nil HackatimeService.fetch_api_key(nil)
  end

  test "fetch_total_seconds_for_projects sends each project name as its own array element" do
    query = nil
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get(%r{/api/v1/users/HT1/stats}) do |env|
        query = env.url.query
        [ 200, { "Content-Type" => "application/json" }, { total_seconds: 2101 }.to_json ]
      end
    end
    connection = Faraday.new(url: "#{HackatimeService::BASE_URL}/api/v1") { |conn| conn.adapter :test, stubs }

    HackatimeService.stub(:connection, connection) do
      assert_equal 2101, HackatimeService.fetch_total_seconds_for_projects("HT1", [ "my,project", "api" ])
    end

    assert_equal [ "my,project", "api" ], Rack::Utils.parse_nested_query(query)["filter_by_project"]
  end

  test "fetch_total_seconds_for_projects refuses a project named only a comma" do
    assert_nil HackatimeService.fetch_total_seconds_for_projects("HT1", [ "," ])
  end
end
