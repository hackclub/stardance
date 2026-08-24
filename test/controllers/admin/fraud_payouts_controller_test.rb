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

  test "preview includes unpaid eligible orders reviewed before this month and credits the first reviewer" do
    order = travel_to(2.months.ago) do
      create_order.tap { |created_order| review!(created_order, @admin, "rejected") }
    end
    review!(order, @other_reviewer, "on_hold")

    sign_in @admin
    get admin_fraud_payouts_path

    assert_response :success
    assert_select ".aorder__card-body", text: /1 unpaid order awaiting payout/
    assert_select "td", text: @admin.display_name, count: 1
    assert_select "td", text: @other_reviewer.display_name, count: 0
  end

  test "preview excludes an eligible order already attached to a payout line" do
    order = create_order
    review!(order, @admin, "rejected")
    run = FraudPayoutRun.create!(period_end: Time.current, total_orders: 1, total_amount: 1000)
    line = run.lines.create!(user: @admin, order_count: 1, amount: 1000)
    order.update_column(:fraud_payout_line_id, line.id)

    sign_in @admin
    get admin_fraud_payouts_path

    assert_response :success
    assert_select ".aorder__card-body", text: /0 unpaid orders awaiting payout/
    assert_select "td", text: @admin.display_name, count: 0
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
