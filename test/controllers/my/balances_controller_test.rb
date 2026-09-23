require "test_helper"

class My::BalancesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = create_user(slack_id: "U_ALICE", display_name: "alice")
    sign_in(@alice)
  end

  # Regression: the page used to redirect to root unless it was a turbo frame
  # request, which made it unreachable once the sidebar modal that framed it
  # was removed.
  test "show renders as a full page navigation" do
    @alice.ledger_entries.create!(amount: 25, reason: "Test payout", ledgerable: @alice)

    get my_balance_path

    assert_response :success
    assert_select "table.space-table"
    assert_select "td", text: "Test payout"
  end

  test "show lists only the signed-in user's entries" do
    bob = create_user(slack_id: "U_BOB", display_name: "bob")
    @alice.ledger_entries.create!(amount: 10, reason: "Alice payout", ledgerable: @alice)
    bob.ledger_entries.create!(amount: 10, reason: "Bob payout", ledgerable: bob)

    get my_balance_path

    assert_response :success
    assert_select "td", text: "Alice payout"
    assert_select "td", text: "Bob payout", count: 0
  end

  test "show renders an empty state with no entries" do
    get my_balance_path

    assert_response :success
    assert_select ".balance-page__empty-title"
  end

  test "show requires a signed-in user" do
    reset!

    get my_balance_path

    assert_response :redirect
  end
end
