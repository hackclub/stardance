require "test_helper"

class AdminPolicyTest < Minitest::Test
  UserStub = Struct.new(:admin_access, :fraud_dept_access, :fulfillment_person_access, :shop_manager_access, :helper_access) do
    def admin? = admin_access
    def fraud_dept? = fraud_dept_access
    def fulfillment_person? = fulfillment_person_access
    def shop_manager? = shop_manager_access
    def helper? = helper_access
  end

  def test_admin_endpoints_access_for_admin
    policy = AdminPolicy.new(UserStub.new(true, false, false, false, false), :admin)

    assert policy.access_admin_endpoints?
  end

  def test_admin_endpoints_access_for_fraud_dept
    policy = AdminPolicy.new(UserStub.new(false, true, false, false, false), :admin)

    assert policy.access_admin_endpoints?
  end

  def test_admin_index_access_for_shop_manager
    policy = AdminPolicy.new(UserStub.new(false, false, false, true, false), :admin)

    assert policy.index?
  end

  def test_fulfillment_view_access_for_fulfillment_person
    policy = AdminPolicy.new(UserStub.new(false, false, true, false, false), :admin)

    assert policy.access_fulfillment_view?
  end
end
