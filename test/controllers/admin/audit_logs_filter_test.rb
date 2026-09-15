require "test_helper"

# The "Performed By" filter used to render an option — and therefore a cachet
# avatar <img> — for every user who had ever appeared in the audit log. Opening
# the page fired ~12k requests and tripped the Cloudflare rate limit, so the
# options are now fetched from /search/users as the admin types.
class Admin::AuditLogsFilterTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(
      slack_id: "U_AUDIT_ADMIN",
      display_name: "audit_admin",
      email: "audit_admin@example.test"
    )
    @admin.grant_role!(:admin)
  end

  test "the filter dropdown renders no options inline" do
    sign_in @admin

    get admin_audit_logs_path
    assert_response :success

    assert_select "[data-searchable-select-target=dropdown]" do
      assert_select "[data-searchable-select-target=option]", count: 0
      assert_select "img", count: 0
    end
  end

  test "the filter points at the user search endpoint" do
    sign_in @admin

    get admin_audit_logs_path

    assert_select "[data-searchable-select-search-url-value=?]",
                  search_users_path(format: :json)
  end

  test "a selected user's name is prefilled without loading every user" do
    sign_in @admin

    get admin_audit_logs_path, params: { whodunnit: @admin.id }
    assert_response :success

    assert_select "input[data-searchable-select-target=input][value=?]", @admin.display_name
  end
end
