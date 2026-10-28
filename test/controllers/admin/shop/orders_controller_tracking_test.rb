require "test_helper"

# Carrier tracking often arrives days after an order is marked fulfilled, so
# it's kept apart from external_ref and can be set in any state. Each change
# is audit logged, and the buyer gets a DM when tracking is added or changed.
class Admin::Shop::OrdersControllerTrackingTest < ActionDispatch::IntegrationTest
  include UserFactory
  include ActiveJob::TestHelper

  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze
  USPS = "9400100000000000000000".freeze
  USPS_URL = "https://tools.usps.com/go/TrackConfirmAction?tLabels=#{USPS}".freeze

  setup do
    @admin = create_user(slack_id: "U_TR_ADMIN", display_name: "tr_admin")
    @admin.grant_role!(:admin)

    item = ShopItem.new(
      name: "Tracked Patch", description: "A physical item",
      ticket_cost: 0, usd_cost: 7, type: "ShopItem::ThirdPartyPhysical", enabled: true
    )
    item.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
    item.save!

    @buyer = create_user(slack_id: "U_TR_BUYER", display_name: "tr_buyer", verified: true)
    @buyer.update!(has_gotten_free_stickers: true)
    @order = @buyer.shop_orders.create!(shop_item: item, quantity: 1, frozen_address: { "country" => "US", "primary" => true })
    @order.update_columns(aasm_state: "fulfilled", fulfilled_at: 1.day.ago, external_ref: "ORD-12345")
  end

  test "tracking can be added after the order is fulfilled, without touching external_ref" do
    sign_in @admin
    post update_tracking_admin_shop_order_path(@order), params: { tracking_number: " #{USPS} " }

    assert_redirected_to admin_shop_order_path(@order)
    @order.reload
    assert_equal USPS, @order.tracking_number
    assert_equal "ORD-12345", @order.external_ref
    assert @order.fulfilled?
  end

  test "a tracking change is audit logged" do
    @order.update_columns(tracking_number: "OLD123")

    sign_in @admin
    post update_tracking_admin_shop_order_path(@order), params: { tracking_number: USPS }

    version = @order.versions.find_by(event: "tracking_updated")
    assert version, "expected a tracking_updated audit entry"
    assert_equal @admin.id.to_s, version.whodunnit.to_s
    assert_equal [ "OLD123", USPS ], version.object_changes["tracking_number"]
  end

  test "adding tracking DMs the buyer" do
    sign_in @admin

    assert_difference -> { tracking_notifications.count }, 1 do
      post update_tracking_admin_shop_order_path(@order), params: { tracking_number: USPS }
    end
    notification = tracking_notifications.last
    assert_equal @buyer, notification.recipient
    assert_enqueued_with(job: NotificationDeliveryJob, args: [ notification.id, "slack" ])
  end

  test "changing tracking DMs the buyer again" do
    @order.update_columns(tracking_number: "OLD123")

    sign_in @admin
    assert_difference -> { tracking_notifications.count }, 1 do
      post update_tracking_admin_shop_order_path(@order), params: { tracking_number: USPS }
    end
  end

  test "resubmitting the same tracking neither DMs nor logs" do
    @order.update_columns(tracking_number: USPS)

    sign_in @admin
    assert_no_difference -> { tracking_notifications.count } do
      assert_no_difference -> { @order.versions.where(event: "tracking_updated").count } do
        post update_tracking_admin_shop_order_path(@order), params: { tracking_number: USPS }
      end
    end
  end

  test "clearing tracking is logged but doesn't DM" do
    @order.update_columns(tracking_number: USPS)

    sign_in @admin
    assert_no_difference -> { tracking_notifications.count } do
      post update_tracking_admin_shop_order_path(@order), params: { tracking_number: "" }
    end
    assert_nil @order.reload.tracking_number
    assert @order.versions.exists?(event: "tracking_updated")
  end

  test "fulfillment staff can set tracking" do
    packer = create_user(slack_id: "U_TR_PACKER", display_name: "tr_packer")
    packer.grant_role!(:fulfillment_person)

    sign_in packer
    post update_tracking_admin_shop_order_path(@order), params: { tracking_number: USPS }

    assert_equal USPS, @order.reload.tracking_number
  end

  test "fraud dept can't set tracking" do
    reviewer = create_user(slack_id: "U_TR_FRAUD", display_name: "tr_fraud")
    reviewer.grant_role!(:fraud_dept)

    sign_in reviewer
    post update_tracking_admin_shop_order_path(@order), params: { tracking_number: USPS }

    assert_nil @order.reload.tracking_number
  end

  test "tracking entered while marking fulfilled rides on the fulfilled DM instead of its own" do
    @order.update_columns(aasm_state: "awaiting_periodical_fulfillment", fulfilled_at: nil)

    sign_in @admin
    assert_no_difference -> { tracking_notifications.count } do
      post mark_fulfilled_admin_shop_order_path(@order), params: { external_ref: "ORD-9", tracking_number: USPS }
    end
    @order.reload
    assert @order.fulfilled?
    assert_equal USPS, @order.tracking_number
  end

  test "the order page shows the linked tracking and the form to change it" do
    @order.update_columns(tracking_number: USPS)

    sign_in @admin
    get admin_shop_order_path(@order)

    assert_response :success
    assert_select "a[href=?]", USPS_URL, text: USPS
    assert_select "form.aorder__tracking-form input[name=tracking_number][value=?]", USPS
  end

  test "the tracking DM links \"here\" to the tracking" do
    @order.update_columns(tracking_number: USPS)
    notification = Notifications::ShopOrders::TrackingUpdated.notify(
      recipient: @buyer, record: @order, params: { "tracking_number" => USPS }
    )

    rendered = ApplicationController.renderer.new.render(
      template: notification.slack_payload[:blocks_path],
      formats: [ :slack_message ],
      locals: notification.slack_locals
    )
    texts = JSON.parse(rendered)["blocks"].filter_map { |block| block.dig("text", "text") }

    assert_equal [
      "hi! your Tracked Patch from stardance is on the way! you can track it <#{USPS_URL}|here> :)",
      "if there's any issues with anything please send a message in <#C0AP0NMSP3P> and you can show it off when it arrives in <#C07UMRYJ1LH>!"
    ], texts
  end

  test "the fulfilled DM never presents an order reference as tracking" do
    assert_includes fulfilled_dm_texts, "*Order reference:* ORD-12345"
    assert_not(fulfilled_dm_texts.any? { |text| text.start_with?("*Tracking:*") })

    @order.update_columns(tracking_number: USPS)
    assert_includes fulfilled_dm_texts, "*Tracking:* <#{USPS_URL}|#{USPS}>"
    assert_includes fulfilled_dm_texts, "*Order reference:* ORD-12345"
  end

  private

  def fulfilled_dm_texts
    rendered = ApplicationController.renderer.new.render(
      template: "notifications/shop_orders/fulfilled",
      formats: [ :slack_message ],
      locals: { order: @order.reload }
    )
    JSON.parse(rendered)["blocks"].flat_map do |block|
      [ block.dig("text", "text"), *Array(block["fields"]).map { |field| field["text"] } ].compact
    end
  end

  def tracking_notifications
    Notifications::ShopOrders::TrackingUpdated.where(record: @order)
  end
end
