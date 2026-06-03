# frozen_string_literal: true

require "test_helper"

class SwAi::ProjectTypeServiceTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:code, :body) do
    def is_a?(klass)
      klass == Net::HTTPSuccess ? code.to_i < 300 : super
    end
  end

  def service_with(response)
    svc = SwAi::ProjectTypeService.new(@project)
    svc.define_singleton_method(:post) { |_uri, _key| response }
    svc
  end

  setup do
    @project = Project.new(title: "My App", description: "A web app")
    Rails.application.config.x.sw_ai.url     = "https://ai.review.example.com"
    Rails.application.config.x.sw_ai.api_key = "test-key"
  end

  test "returns type on success" do
    result = service_with(FakeResponse.new("200", { "type" => "Web App" }.to_json)).call
    assert result.ok
    assert_equal "Web App", result.type
  end

  test "treats Unknown as nil type" do
    result = service_with(FakeResponse.new("200", { "type" => "Unknown" }.to_json)).call
    assert result.ok
    assert_nil result.type
  end

  test "returns not-ok on non-200 response" do
    result = service_with(FakeResponse.new("422", "")).call
    assert_not result.ok
    assert_nil result.type
  end

  test "returns not-ok when api key is blank" do
    Rails.application.config.x.sw_ai.api_key = nil
    result = SwAi::ProjectTypeService.new(@project).call
    assert_not result.ok
    assert_nil result.type
  end

  test "re-raises on network error" do
    svc = SwAi::ProjectTypeService.new(@project)
    svc.define_singleton_method(:post) { |_uri, _key| raise Errno::ECONNREFUSED }
    assert_raises(Errno::ECONNREFUSED) { svc.call }
  end
end
