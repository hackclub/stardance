require "test_helper"

class Admin::CertificatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(slack_id: "U_CERT_ADMIN", display_name: "cert_admin", email: "cert_admin@example.test")
    @admin.grant_role!(:admin)

    @certificate = Certificate.create!(user: users(:one), name: "Custom Name", hours_at_issue: 31)
    assert @certificate.pending?
  end

  test "admin sees the pending queue" do
    sign_in @admin

    get admin_certificates_path

    assert_response :success
    assert_match "Custom Name", response.body
  end

  test "non-admin is denied" do
    sign_in users(:two)

    get admin_certificates_path

    assert_response :not_found
  end

  test "admin can approve a pending name" do
    sign_in @admin

    post admin_certificate_approval_path(@certificate), params: { name: @certificate.name }

    assert_redirected_to admin_certificates_path
    assert @certificate.reload.approved?
    assert_equal @admin.id.to_s, @certificate.versions.last.whodunnit
    assert @certificate.user.achievements.exists?(achievement_slug: "certificate_earned")
    assert_not @admin.achievements.exists?(achievement_slug: "certificate_earned")
  end

  test "admin can reject a pending name" do
    sign_in @admin

    post admin_certificate_rejection_path(@certificate), params: { name: @certificate.name }

    assert_redirected_to admin_certificates_path
    assert @certificate.reload.rejected?
    assert_not @certificate.user.achievements.exists?(achievement_slug: "certificate_earned")
  end

  test "approving with a stale name is refused" do
    sign_in @admin

    post admin_certificate_approval_path(@certificate), params: { name: "Old Displayed Name" }

    assert_redirected_to admin_certificates_path
    assert @certificate.reload.pending?
    assert_not @certificate.user.achievements.exists?(achievement_slug: "certificate_earned")
    assert_match "changed", flash[:alert]
  end

  test "reviewing an already-reviewed certificate redirects with a notice" do
    @certificate.approved!
    sign_in @admin

    post admin_certificate_rejection_path(@certificate), params: { name: @certificate.name }

    assert_redirected_to admin_certificates_path
    assert @certificate.reload.approved?
    assert_match "already reviewed", flash[:alert]
  end
end
