require "test_helper"

class Admin::Users::OrderRejectionsControllerTest < ActionDispatch::IntegrationTest
  include UserFactory

  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze

  setup do
    @admin = create_user(slack_id: "U_ORDER_REJECT_ADMIN", display_name: "order_reject_admin")
    @admin.grant_role!(:admin)
    @customer = create_user(slack_id: "U_ORDER_REJECT_CUSTOMER", display_name: "order_reject_customer")
    @project = Project.create!(title: "Fraud review")
    @item = ShopItem.new(
      name: "Mass rejection test item",
      description: "Test item",
      ticket_cost: 0,
      usd_cost: 0,
      type: "ShopItem::ThirdPartyPhysical",
      enabled: true
    )
    @item.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "pixel.png", content_type: "image/png")
    @item.save!
    @order = @customer.shop_orders.create!(
      shop_item: @item,
      quantity: 1,
      frozen_address: { "country" => "US", "primary" => true }
    )
  end

  test "rejects pending orders with required fraud audit details" do
    sign_in @admin

    post admin_user_order_rejection_path(@customer), params: {
      reason: "Order rejected",
      internal_rejection_reason: "Confirmed abuse",
      fraud_related_project_id: @project.id,
      joe_case_url: "https://telescreen.hackclub.com/cases/123"
    }

    assert_redirected_to admin_user_path(@customer)
    assert_equal "Rejected 1 order(s) for #{@customer.display_name}.", flash[:notice]
    assert_predicate @order.reload, :rejected?
    assert_equal "Order rejected", @order.rejection_reason
    assert_equal "Confirmed abuse", @order.internal_rejection_reason
    assert_equal @project, @order.fraud_related_project
    assert_equal "https://telescreen.hackclub.com/cases/123", @order.joe_case_url
  end

  test "reports validation failures instead of claiming success" do
    sign_in @admin

    post admin_user_order_rejection_path(@customer), params: { reason: "Order rejected" }

    assert_redirected_to admin_user_path(@customer)
    assert_match(/1 failed/, flash[:alert])
    assert_predicate @order.reload, :pending?
  end
end
