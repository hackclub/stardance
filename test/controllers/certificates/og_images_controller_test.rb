require "test_helper"

class Certificates::OgImagesControllerTest < ActionDispatch::IntegrationTest
  include CertificateFactory

  setup do
    @user = users(:one)
  end

  test "renders a png for a valid approved code" do
    create_approved_ship(@user, hours: 42)
    certificate = Certificate.create!(user: @user, name: "Orpheus Star", hours_at_issue: 42)
    certificate.approved!

    get certificate_og_image_path(code: certificate.code.downcase)

    assert_response :success
    assert_equal "image/png", response.media_type
  end

  test "renders names containing markup characters" do
    create_approved_ship(@user, hours: 42)
    certificate = Certificate.create!(user: @user, name: "Ben & Jerry <3", hours_at_issue: 42)
    certificate.approved!

    get certificate_og_image_path(code: certificate.code)

    assert_response :success
    assert_equal "image/png", response.media_type
  end

  test "returns not found for an unknown code" do
    get certificate_og_image_path(code: "Z9Z9Z9")

    assert_response :not_found
  end

  test "returns not found while the certificate is pending" do
    create_approved_ship(@user, hours: 42)
    certificate = Certificate.create!(user: @user, name: "Custom Name", hours_at_issue: 42)
    assert certificate.pending?

    get certificate_og_image_path(code: certificate.code)

    assert_response :not_found
  end
end
