require "test_helper"

class Admin::Users::OrderRejectionsControllerTest < ActionDispatch::IntegrationTest
  include UserFactory

  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze

  setup do
    @admin = create_user(slack_id: "U_ORDER_REJECT_ADMIN", display_name: "order_reject_admin")
    @admin.grant_role!(:admin)
    @admin.grant_role!(:fraud_dept)
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
    @customer.update!(has_gotten_free_stickers: true) # clears the shop-tutorial gate
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

  test "rejects orders against a project the user has since deleted" do
    @project.soft_delete!(force: true)
    sign_in @admin

    post admin_user_order_rejection_path(@customer), params: {
      internal_rejection_reason: "Unbanning, clearing old orders first",
      fraud_related_project_id: @project.id
    }

    assert_equal "Rejected 1 order(s) for #{@customer.display_name}.", flash[:notice]
    assert_predicate @order.reload, :rejected?
    assert_equal @project, @order.fraud_related_project
  end

  test "the reject form offers the user's deleted projects" do
    Project::Membership.create!(project: @project, user: @customer, role: :owner)
    @project.soft_delete!(force: true)
    sign_in @admin

    get admin_user_path(@customer)

    assert_select "#reject-modal-orders select[name=fraud_related_project_id] option[value=?]", @project.id.to_s,
                  text: "Fraud review (##{@project.id}, deleted)"
  end

  test "reports validation failures instead of claiming success" do
    sign_in @admin

    post admin_user_order_rejection_path(@customer), params: { reason: "Order rejected" }

    assert_redirected_to admin_user_path(@customer)
    assert_match(/1 failed/, flash[:alert])
    assert_predicate @order.reload, :pending?
  end

  test "a plain admin without the fraud role doesn't need or see the fraud fields" do
    Project.create!(id: Admin::ShopOrderRejector::PLACEHOLDER_FRAUD_PROJECT_ID, title: "Stardance")
    plain_admin = create_user(slack_id: "U_ORDER_REJECT_PLAIN_ADMIN", display_name: "plain_admin")
    plain_admin.grant_role!(:admin)
    sign_in plain_admin

    get admin_user_path(@customer)
    assert_select "#reject-modal-orders select[name=fraud_related_project_id]", count: 0
    assert_select "#reject-modal-orders textarea[name=internal_rejection_reason]", count: 0

    post admin_user_order_rejection_path(@customer), params: { reason: "Order rejected" }

    assert_redirected_to admin_user_path(@customer)
    assert_equal "Rejected 1 order(s) for #{@customer.display_name}.", flash[:notice]
    assert_predicate @order.reload, :rejected?
    assert_equal "Order rejected", @order.internal_rejection_reason
  end

  test "the fraud fields are hidden once the only orders left are past fraud review" do
    @order.update_columns(aasm_state: "awaiting_periodical_fulfillment")
    sign_in @admin

    get admin_user_path(@customer)

    assert_select "#reject-modal-orders select[name=fraud_related_project_id]", count: 0
    assert_select "#reject-modal-orders textarea[name=internal_rejection_reason]", count: 0
  end
end
