require "test_helper"

# == Schema Information
#
# Table name: shop_suggestions
#
#  id               :bigint           not null, primary key
#  aasm_state       :string           default("pending"), not null
#  description      :text
#  discarded_at     :datetime
#  name             :text
#  rejection_reason :string
#  url              :string
#  usd_cost         :decimal(8, 2)
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  shop_item_id     :bigint
#  user_id          :bigint           not null
#
# Indexes
#
#  index_shop_suggestions_on_aasm_state    (aasm_state)
#  index_shop_suggestions_on_shop_item_id  (shop_item_id)
#  index_shop_suggestions_on_user_id       (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class ShopSuggestionTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    LedgerEntry.create!(user: @user, ledgerable: @user, amount: 1_000_000, reason: "Test balance top-up")
  end

  test "usd_cost must fit within the decimal(8,2) column" do
    suggestion = build_suggestion(usd_cost: 999_999.99)
    assert suggestion.valid?, suggestion.errors.full_messages.to_sentence

    suggestion = build_suggestion(usd_cost: 1_000_000)
    assert_not suggestion.valid?
    assert_includes suggestion.errors[:usd_cost], "must be less than 1000000"
  end

  test "saving a suggestion with an out-of-range usd_cost does not raise" do
    suggestion = build_suggestion(usd_cost: 1_000_000)
    assert_not suggestion.save
  end

  private

  def build_suggestion(usd_cost:)
    @user.shop_suggestions.build(
      name: "Silly suggestion",
      description: "A suggestion with a silly cost",
      usd_cost: usd_cost,
      image: png_upload
    )
  end

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
