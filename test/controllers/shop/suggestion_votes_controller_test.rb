require "test_helper"

class Shop::SuggestionVotesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Flipper.enable(:shop_suggestions)
    @user = users(:one)
    LedgerEntry.create!(user: @user, ledgerable: @user, amount: 100, reason: "Test balance top-up")
    sign_in(@user)
  end

  test "voting on a suggestion that doesn't exist redirects back with an alert instead of 404ing" do
    post shop_suggestion_votes_path(999_999_999)

    assert_redirected_to shop_suggestions_path
    assert_equal "That suggestion no longer exists.", flash[:alert]
  end

  test "voting on an existing pending suggestion succeeds" do
    other_user = users(:two)
    LedgerEntry.create!(user: other_user, ledgerable: other_user, amount: 100, reason: "Test balance top-up")
    suggestion = other_user.shop_suggestions.create!(
      name: "Existing suggestion",
      description: "A perfectly valid suggestion",
      usd_cost: 29.99,
      image: png_upload
    )

    post shop_suggestion_votes_path(suggestion)

    assert_redirected_to shop_suggestions_path
    assert_equal 1, suggestion.reload.vote_count
  end

  private

  # A real 1x1 PNG so ActiveStorage's spoofing protection accepts it.
  def png_upload
    data = Base64.decode64(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    )
    file = Tempfile.new([ "suggestion", ".png" ])
    file.binmode
    file.write(data)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "image/png")
  end
end
