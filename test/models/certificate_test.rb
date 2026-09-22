require "test_helper"

# == Schema Information
#
# Table name: certificates
#
#  id             :bigint           not null, primary key
#  code           :string           not null
#  hours_at_issue :float            not null
#  name           :string           not null
#  status         :string           default("pending"), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  user_id        :bigint           not null
#
# Indexes
#
#  index_certificates_on_code     (code) UNIQUE
#  index_certificates_on_user_id  (user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class CertificateTest < ActiveSupport::TestCase
  include CertificateFactory

  test "generates an alternating letter-digit code on create" do
    certificate = Certificate.create!(user: users(:one), name: "Test Star", hours_at_issue: 31.5)

    assert_match Certificate::CODE_FORMAT, certificate.code
    refute_match(/[IO01]/, certificate.code)
  end

  test "allows only one certificate per user" do
    Certificate.create!(user: users(:one), name: "First", hours_at_issue: 31)
    duplicate = Certificate.new(user: users(:one), name: "Second", hours_at_issue: 31)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], "has already been taken"
  end

  test "requires a name within the length cap" do
    certificate = Certificate.new(user: users(:one), name: "x" * (Certificate::NAME_MAX_LENGTH + 1), hours_at_issue: 31)

    assert_not certificate.valid?
    assert certificate.errors[:name].any?
  end

  test "normalize_code upcases and strips non-alphanumerics" do
    assert_equal "C5A8G9", Certificate.normalize_code(" c5-a8 g9 ")
  end

  test "request_with auto-approves names matching the verified identity" do
    user = users(:one)
    user.update!(first_name: "Orpheus", last_name: "Dino")

    certificate = user.build_certificate(hours_at_issue: 31)
    assert certificate.request_with("orpheus dino")
    assert certificate.approved?
  end

  test "request_with stores the verified spelling when the match is loose" do
    user = users(:one)
    user.update!(first_name: "Orpheus", last_name: "Dino")

    certificate = user.build_certificate(hours_at_issue: 31)
    assert certificate.request_with("  oRpHeUs   DiNo ")
    assert certificate.approved?
    assert_equal "Orpheus Dino", certificate.name
  end

  test "request_with squishes custom names before review" do
    user = users(:one)
    user.update!(first_name: "Orpheus", last_name: "Dino")

    certificate = user.build_certificate(hours_at_issue: 31)
    assert certificate.request_with("  Custom   Name ")
    assert certificate.pending?
    assert_equal "Custom Name", certificate.name
  end

  test "request_with sends custom names to review" do
    user = users(:one)
    user.update!(first_name: "Orpheus", last_name: "Dino")

    certificate = user.build_certificate(hours_at_issue: 31)
    assert certificate.request_with("Someone Else")
    assert certificate.pending?
  end

  test "request_with re-queues a rejected certificate even for the identical name" do
    user = users(:one)
    certificate = user.build_certificate(hours_at_issue: 31)
    certificate.request_with("Custom Name")
    certificate.rejected!

    assert certificate.request_with("Custom Name")
    assert certificate.pending?
  end

  test "certificate_eligible? keys off approved hours" do
    user = users(:one)
    assert_not user.certificate_eligible?

    create_approved_ship(user, hours: Certificate::REQUIRED_APPROVED_HOURS)
    assert user.certificate_eligible?
  end

  test "approved hours exclude soft-deleted projects" do
    user = users(:one)
    create_approved_ship(user, hours: 42)
    assert_equal 42, user.approved_hours

    posts(:one).project.soft_delete!(force: true)
    assert_equal 0, user.approved_hours
    assert_not user.certificate_eligible?
  end

  test "approved funding counts the design time a hardware ship leaves out" do
    user = users(:one)
    user.update_columns(verification_status: "verified", ysws_eligible: true)
    project = Project.create!(title: "Funded Rover", hardware_stage: "design", created_at: 5.days.ago)
    Project::Membership.create!(project: project, user: user, role: :owner)
    create_devlog(project, user, seconds: 2 * 3600, phase: "design", at: 3.days.ago)
    request = project.certification_funding_requests.create!(
      user: user, complexity_tier: 1, requested_amount_cents: 2_000, status: :pending
    )
    request.update_column(:created_at, 2.days.ago)
    create_devlog(project, user, seconds: 3 * 3600, phase: "build", at: 1.day.ago)

    assert_equal 0, user.approved_hours

    request.update_column(:status, Certification::FundingRequest.statuses[:approved])

    assert_in_delta 2.0, user.approved_hours, 0.001
  end

  private

  def create_devlog(project, user, seconds:, phase:, at:)
    devlog = Post::Devlog.new(body: "work log", duration_seconds: seconds, phase: phase)
    devlog.uploading_attachments = true
    devlog.save!
    Post.create!(project: project, user: user, postable: devlog, created_at: at)
  end
end
