require "test_helper"

class Admin::FraudPayoutsControllerTest < ActionDispatch::IntegrationTest
  include UserFactory

  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze

  setup do
    @admin = create_user(slack_id: "UFRAUDPAYOUTADMIN", display_name: "fraud_payout_admin")
    @admin.grant_role!(:admin)
    @other_reviewer = create_user(slack_id: "UFRAUDPAYOUTOTHER", display_name: "fraud_payout_other")
    @buyer = create_user(slack_id: "UFRAUDPAYOUTBUYER", display_name: "fraud_payout_buyer")
    @buyer.update!(has_gotten_free_stickers: true)

    @item = ShopItem.new(
      name: "Fraud payout test item",
      description: "An item for payout preview tests",
      ticket_cost: 0,
      type: "ShopItem::ThirdPartyPhysical",
      enabled: true
    )
    @item.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
    @item.save!
  end

  test "the leaderboard ranks reviewers by stardust and breaks out each source" do
    FraudReviewPayout.create!(reviewer: @admin, subject: @buyer, flag_count: 1, order_count: 2,
                              integrity_count: 3, amount: 9.5, completed_at: Time.current)
    FraudReviewPayout.create!(reviewer: @other_reviewer, subject: @buyer, flag_count: 1,
                              order_count: 0, integrity_count: 0, amount: 1.1, completed_at: Time.current)

    sign_in @admin
    get admin_fraud_payouts_path

    assert_response :success
    assert_select "td", text: /#{@admin.display_name}/
    assert_select ".fraud-leaderboard__row--me td", text: "6", count: 1
    assert_select "tbody tr:first-child td", text: /#{@admin.display_name}/,
                  count: 1, message: "the bigger earner sorts first"
  end

  test "an unfinished tally stays off the leaderboard" do
    FraudReviewPayout.create!(reviewer: @admin, subject: @buyer, flag_count: 1,
                              order_count: 0, integrity_count: 0, amount: 1.1)

    sign_in @admin
    get admin_fraud_payouts_path

    assert_response :success
    assert_select ".fraud-payouts__empty", text: /Nobody has cleared a person yet/
  end

  test "triggering a manual run queues the calculation job" do
    sign_in @admin

    assert_enqueued_with(job: ::Fraud::CalculatePayoutsJob,
                         args: [ { manual: true, triggered_by: @admin } ]) do
      post trigger_admin_fraud_payouts_path
    end

    assert_redirected_to admin_fraud_payouts_path
  end

  private

  def create_order
    ShopOrder.create!(
      user: @buyer,
      shop_item: @item,
      quantity: 1,
      frozen_item_price: 0,
      frozen_address: { "country" => "US" }.to_json,
      aasm_state: "pending"
    )
  end

  def review!(order, reviewer, state)
    attrs = { aasm_state: state }
    if state == "rejected"
      attrs[:internal_rejection_reason] = "flagged as fraud"
      attrs[:fraud_related_project_id] = projects(:one).id
    end

    PaperTrail.request(whodunnit: reviewer.id) { order.update!(attrs) }
  end
end
