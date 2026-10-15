require "test_helper"

class BukuX3::AssignmentTest < ActiveSupport::TestCase
  UserStub = Data.define(:id)
  TEST_SECRET = "bukux3-test-secret"

  test "discovery counts start at zero" do
    assert_equal({ total: 0, buku: 0, bean: 0 }, BukuX3::Assignment.discovered_counts)
  end

  test "counts only saved reveals once, split using the real assignment" do
    discovered = [ users(:one), users(:two) ]
    discovered.each do |user|
      user.dismiss_thing!(BukuX3RevealComponent::DISMISS_THING)
      user.dismiss_thing!(BukuX3RevealComponent::DISMISS_THING)
    end
    users(:three).dismiss_thing!(VisualNovelComponent::BUKU_X3_DISMISS_THING)
    buku_count = discovered.count { |user| BukuX3::Assignment.buku?(user) }
    expected = { total: 2, buku: buku_count, bean: 2 - buku_count }
    assert_no_difference "PaperTrail::Version.count" do
      2.times { assert_equal expected, BukuX3::Assignment.discovered_counts }
    end
  end

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
