require "test_helper"

class SemanticSearchTest < ActiveSupport::TestCase
  # Cached results come back from Redis as JSON. Views read them with symbol
  # keys (item[:path]), so a string-keyed cache hit would render every result
  # as a link back to /search/global.
  test "cached results keep symbol keys" do
    fresh = SemanticSearch.empty_results.merge(
      "devlog" => [ { type: "devlog", id: 1, title: "IELTS prep", subtitle: "Devlog", preview: "", path: "/projects/1/devlogs/1" } ]
    )
    redis = Struct.new(:store) do
      def get(key) = store[key]
      def set(key, value, **) = store[key] = value
    end.new({})

    SemanticSearch.stub(:redis_url, "redis://localhost:6379") do
      SemanticSearch.stub(:redis, redis) do
        SemanticSearch.stub(:search_without_cache, fresh) do
          SemanticSearch.search("ielts", viewer: nil, surface: "discover_rail")
        end

        cached = SemanticSearch.search("ielts", viewer: nil, surface: "discover_rail")

        assert_equal "/projects/1/devlogs/1", cached.fetch("devlog").first[:path]
        assert_equal "IELTS prep", cached.fetch("devlog").first[:title]
      end
    end
  end
end
