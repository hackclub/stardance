require "test_helper"

class CertificatesControllerTest < ActionDispatch::IntegrationTest
  include CertificateFactory

  setup do
    @user = users(:one)
  end

  test "verify page renders publicly" do
    get certificate_path
    assert_response :success
  end

  test "shows the holder and projects for a valid approved code" do
    create_approved_ship(@user, hours: 42)
    certificate = Certificate.create!(user: @user, name: "Orpheus Star", hours_at_issue: 42)
    certificate.approved!

    get certificate_path(code: certificate.code.downcase)

    assert_response :success
    assert_match "This certificate is valid", response.body
    assert_match "Orpheus Star", response.body
    assert_match "42 approved hours", response.body
    assert_match CGI.escapeHTML(certificate_og_image_url(code: certificate.code, format: :png)), response.body
    assert_match "Orpheus Star&#39;s Stardance Certificate", response.body
  end

  test "pending certificates do not verify" do
    create_approved_ship(@user, hours: 42)
    certificate = Certificate.create!(user: @user, name: "Custom Name", hours_at_issue: 42)
    assert certificate.pending?

    get certificate_path(code: certificate.code)

    assert_response :success
    assert_match "No certificate found", response.body
  end

  test "shows a not-found state for an unknown code" do
    get certificate_path(code: "Z9Z9Z9")

    assert_response :success
    assert_match "No certificate found", response.body
  end

  test "request with a name matching verified identity issues instantly" do
    @user.update!(first_name: "Orpheus", last_name: "Dino")
    create_approved_ship(@user, hours: 31)
    sign_in @user

    assert_difference "Certificate.count", 1 do
      post certificate_path, params: { certificate: { name: "Orpheus Dino" } }
    end

    assert_redirected_to certificate_path
    assert @user.reload.certificate.approved?
    assert @user.achievements.exists?(achievement_slug: "certificate_earned")
  end

  test "request with a custom name goes to review" do
    @user.update!(first_name: "Orpheus", last_name: "Dino")
    create_approved_ship(@user, hours: 31)
    sign_in @user

    assert_difference "Certificate.count", 1 do
      post certificate_path, params: { certificate: { name: "My Real Name" } }
    end

    assert_redirected_to certificate_path
    certificate = @user.reload.certificate
    assert_equal "My Real Name", certificate.name
    assert certificate.pending?
    assert_in_delta 31.0, certificate.hours_at_issue
    assert_not @user.achievements.exists?(achievement_slug: "certificate_earned")
  end

  test "existing approved holders receive the achievement on the achievements page" do
    certificate = @user.create_certificate!(name: "Existing Holder", hours_at_issue: 31)
    certificate.update_column(:status, "approved")
    Flipper.enable(:week_2_release)
    sign_in @user

    assert_difference -> { @user.achievements.where(achievement_slug: "certificate_earned").count }, 1 do
      get my_achievements_path
    end

    assert_response :success
    assert_select "#achievement-certificate_earned.achievements__card--earned", text: /Certified Stardancer/
    assert_no_difference -> { @user.achievements.where(achievement_slug: "certificate_earned").count } do
      get my_achievements_path
    end
  ensure
    Flipper.disable(:week_2_release)
  end

  test "request without a certificate param falls back to the verified name" do
    @user.update!(first_name: "Orpheus", last_name: "Dino")
    create_approved_ship(@user, hours: 31)
    sign_in @user

    assert_difference "Certificate.count", 1 do
      post certificate_path
    end

    assert_redirected_to certificate_path
    certificate = @user.reload.certificate
    assert_equal "Orpheus Dino", certificate.name
    assert certificate.approved?
  end

  test "rejected user can re-request with a different name" do
    create_approved_ship(@user, hours: 31)
    certificate = Certificate.create!(user: @user, name: "Bad Name", hours_at_issue: 31)
    certificate.rejected!
    sign_in @user

    patch certificate_path, params: { certificate: { name: "Better Name" } }

    assert_redirected_to certificate_path
    certificate.reload
    assert_equal "Better Name", certificate.name
    assert certificate.pending?
  end

  test "re-requesting the identical rejected name re-enters the review queue" do
    create_approved_ship(@user, hours: 31)
    certificate = Certificate.create!(user: @user, name: "Bad Name", hours_at_issue: 31)
    certificate.rejected!
    sign_in @user

    patch certificate_path, params: { certificate: { name: "Bad Name" } }

    assert_redirected_to certificate_path
    assert certificate.reload.pending?
  end

  test "re-request refreshes the hours snapshot" do
    create_approved_ship(@user, hours: 31)
    certificate = Certificate.create!(user: @user, name: "Bad Name", hours_at_issue: 31)
    certificate.rejected!
    create_approved_ship(@user, hours: 60)
    sign_in @user

    patch certificate_path, params: { certificate: { name: "Better Name" } }

    assert_in_delta 60.0, certificate.reload.hours_at_issue
  end

  test "re-request is forbidden once the holder no longer qualifies" do
    create_approved_ship(@user, hours: 31)
    certificate = Certificate.create!(user: @user, name: "Custom Name", hours_at_issue: 31)
    certificate.rejected!
    post_ship_events(:one).update_columns(certification_status: "pending")
    sign_in @user

    patch certificate_path, params: { certificate: { name: "Another Name" } }

    assert_response :forbidden
    assert certificate.reload.rejected?
  end

  test "download renders names containing markup characters" do
    create_approved_ship(@user, hours: 31)
    certificate = Certificate.create!(user: @user, name: "Ben & Jerry <3", hours_at_issue: 31)
    certificate.approved!
    sign_in @user

    get download_certificate_path

    assert_response :success
    assert_equal "application/pdf", response.media_type
  end

  test "re-request is forbidden unless rejected" do
    create_approved_ship(@user, hours: 31)
    Certificate.create!(user: @user, name: "Pending Name", hours_at_issue: 31)
    sign_in @user

    patch certificate_path, params: { certificate: { name: "Sneaky Change" } }

    assert_response :forbidden
    assert_equal "Pending Name", @user.reload.certificate.name
  end

  test "ineligible user cannot request a certificate" do
    sign_in @user

    assert_no_difference "Certificate.count" do
      post certificate_path, params: { certificate: { name: "My Real Name" } }
    end

    assert_response :forbidden
  end

  test "user cannot request a second certificate" do
    create_approved_ship(@user, hours: 31)
    Certificate.create!(user: @user, name: "First", hours_at_issue: 31)
    sign_in @user

    assert_no_difference "Certificate.count" do
      post certificate_path, params: { certificate: { name: "Second" } }
    end

    assert_response :forbidden
  end

  test "owner can download their approved certificate as pdf" do
    create_approved_ship(@user, hours: 31)
    certificate = Certificate.create!(user: @user, name: "Orpheus Star", hours_at_issue: 31)
    certificate.approved!
    sign_in @user

    get download_certificate_path

    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert_includes response.headers["Content-Disposition"], "stardance-certificate-#{certificate.code}.pdf"
  end

  test "owner sees share buttons for their approved certificate" do
    create_approved_ship(@user, hours: 31)
    certificate = Certificate.create!(user: @user, name: "Orpheus Star", hours_at_issue: 31)
    certificate.approved!
    sign_in @user

    get certificate_path

    assert_response :success
    share_url = certificate_url(code: certificate.code)
    assert_match "https://www.linkedin.com/sharing/share-offsite/?#{{ url: share_url }.to_query}", response.body
    assert_match "https://www.linkedin.com/profile/add?", response.body
    assert_match CGI.escapeHTML(certificate.code), response.body
    assert_match "https://x.com/intent/post", response.body
    assert_match CGI.escapeHTML(share_url), response.body
  end

  test "download is forbidden while the name is under review" do
    create_approved_ship(@user, hours: 31)
    Certificate.create!(user: @user, name: "Custom Name", hours_at_issue: 31)
    sign_in @user

    get download_certificate_path

    assert_response :forbidden
  end

  test "download requires a certificate" do
    sign_in @user

    get download_certificate_path

    assert_response :forbidden
  end

  test "regenerate refreshes hours and keeps name when matching verified identity" do
    @user.update!(first_name: "Orpheus", last_name: "Dino")
    create_approved_ship(@user, hours: 31)
    certificate = Certificate.create!(user: @user, name: "Orpheus Dino", hours_at_issue: 31)
    certificate.approved!
    create_approved_ship(@user, hours: 60)
    sign_in @user

    patch regenerate_certificate_path, params: { certificate: { name: "Orpheus Dino" } }

    assert_redirected_to certificate_path
    certificate.reload
    assert certificate.approved?
    assert_in_delta 60.0, certificate.hours_at_issue
  end

  test "regenerate with a custom name re-enters review" do
    @user.update!(first_name: "Orpheus", last_name: "Dino")
    create_approved_ship(@user, hours: 31)
    certificate = Certificate.create!(user: @user, name: "Orpheus Dino", hours_at_issue: 31)
    certificate.approved!
    sign_in @user

    patch regenerate_certificate_path, params: { certificate: { name: "Different Name" } }

    assert_redirected_to certificate_path
    certificate.reload
    assert_equal "Different Name", certificate.name
    assert certificate.pending?
  end

  test "regenerate is forbidden for pending certificates" do
    create_approved_ship(@user, hours: 31)
    Certificate.create!(user: @user, name: "Pending Name", hours_at_issue: 31)
    sign_in @user

    patch regenerate_certificate_path, params: { certificate: { name: "New Name" } }

    assert_response :forbidden
  end

  test "regenerate is forbidden for rejected certificates" do
    create_approved_ship(@user, hours: 31)
    certificate = Certificate.create!(user: @user, name: "Bad Name", hours_at_issue: 31)
    certificate.rejected!
    sign_in @user

    patch regenerate_certificate_path, params: { certificate: { name: "New Name" } }

    assert_response :forbidden
  end

  test "regenerate is forbidden for ineligible users" do
    create_approved_ship(@user, hours: 31)
    certificate = Certificate.create!(user: @user, name: "Some Name", hours_at_issue: 31)
    certificate.approved!
    post_ship_events(:one).update_columns(certification_status: "pending")
    sign_in @user

    patch regenerate_certificate_path, params: { certificate: { name: "Some Name" } }

    assert_response :forbidden
  end

  test "approved certificate page shows regenerate option" do
    create_approved_ship(@user, hours: 31)
    certificate = Certificate.create!(user: @user, name: "Orpheus Star", hours_at_issue: 31)
    certificate.approved!
    sign_in @user

    get certificate_path

    assert_response :success
    assert_match "Need to update your name or hours?", response.body
    assert_match "Regenerate certificate", response.body
  end
end
