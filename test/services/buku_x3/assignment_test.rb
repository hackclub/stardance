require "test_helper"

class BukuX3::AssignmentTest < ActiveSupport::TestCase
  UserStub = Data.define(:id)
  TEST_SECRET = "bukux3-test-secret"

  test "assignment is stable for the same account" do
    user = UserStub.new(42)

    results = Array.new(10) { BukuX3::Assignment.buku?(user, secret: TEST_SECRET) }

    assert_equal 1, results.uniq.size
  end

  test "assignment distributes accounts evenly between both roles" do
    buku_count = (1..10_000).count do |id|
      BukuX3::Assignment.buku?(UserStub.new(id), secret: TEST_SECRET)
    end

    assert_in_delta 5_000, buku_count, 150
  end
end
