require "test_helper"

class Admin::ViralityReviewPolicyTest < ActiveSupport::TestCase
  test "only admins and super admins can access every review action" do
    [ nil, [], [ "project_certifier" ], [ "fraud_dept" ], [ "nda_helper" ], [ "admin" ], [ "super_admin" ] ].each do |roles|
      user = roles.nil? ? nil : User.new(granted_roles: roles)
      policy = Admin::ViralityReviewPolicy.new(user, :virality_review)
      expected = roles&.intersect?(%w[admin super_admin]) || false
      assert_equal expected, !!user&.admin?
      %i[index? show? create? cancel?].each { |action| assert_equal expected, !!policy.public_send(action), "#{roles.inspect}: #{action}" }
    end
  end
end
