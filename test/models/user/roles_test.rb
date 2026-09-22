require "test_helper"

class User::RolesTest < ActiveSupport::TestCase
  test "the fraud squad can do everything the fraud department can" do
    assert_predicate User.new(granted_roles: [ "fraud_fraud_squad_squad" ]), :fraud_dept?
    assert_not_predicate User.new(granted_roles: [ "fraud_dept" ]), :fraud_fraud_squad_squad?
  end

  test "an implied role can still be granted and removed on its own" do
    squad = create_user(slack_id: "U_ROLES_SQUAD", display_name: "roles_squad")
    squad.grant_role!(:fraud_fraud_squad_squad)

    squad.grant_role!(:fraud_dept)
    assert_equal %i[fraud_fraud_squad_squad fraud_dept], squad.reload.roles

    squad.remove_role!(:fraud_dept)
    assert_equal %i[fraud_fraud_squad_squad], squad.reload.roles
  end
end
