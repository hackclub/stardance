# == Schema Information
#
# Table name: users
#
#  id                           :bigint           not null, primary key
#  age_attestation              :string
#  banned                       :boolean          default(FALSE), not null
#  banned_at                    :datetime
#  banned_reason                :text
#  bio                          :text
#  display_name                 :string
#  email                        :string
#  enriched_ref                 :string
#  experience_level             :string
#  first_name                   :string
#  geocoded_country             :string
#  geocoded_lat                 :float
#  geocoded_lon                 :float
#  geocoded_subdivision         :string
#  granted_roles                :string           default([]), not null, is an Array
#  guest_email                  :string
#  has_gotten_free_stickers     :boolean          default(FALSE)
#  has_pending_achievements     :boolean          default(FALSE), not null
#  hcb_email                    :string
#  interests                    :string           default([]), is an Array
#  internal_notes               :text
#  ip_address                   :string
#  last_name                    :string
#  manual_ysws_override         :boolean
#  mission_review_notifications :boolean          default(TRUE), not null
#  onboarded_at                 :datetime
#  ref                          :string
#  regions                      :string           default([]), is an Array
#  session_token                :string
#  shop_region                  :enum
#  shop_tutorial_completed_at   :datetime
#  shop_tutorial_started_at     :datetime
#  synced_at                    :datetime
#  things_dismissed             :string           default([]), not null, is an Array
#  user_agent                   :string
#  user_ref                     :string
#  verification_checked_at      :datetime
#  verification_status          :string           default("needs_submission"), not null
#  vote_balance                 :integer          default(0), not null
#  votes_count                  :integer
#  ysws_eligible                :boolean          default(FALSE), not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  slack_id                     :string
#
# Indexes
#
#  index_users_on_email                      (email)
#  index_users_on_lower_display_name_unique  (lower((display_name)::text)) UNIQUE WHERE ((display_name IS NOT NULL) AND ((display_name)::text <> ''::text))
#  index_users_on_lower_email_unique         (lower((email)::text)) UNIQUE WHERE ((email IS NOT NULL) AND ((email)::text <> ''::text))
#  index_users_on_onboarded_at               (onboarded_at)
#  index_users_on_session_token              (session_token) UNIQUE
#  index_users_on_slack_id                   (slack_id) UNIQUE
#
require "test_helper"

class UserTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
  end

  test "roles are granted and removed through the user API" do
    user = users(:one)
    user.update!(granted_roles: [])

    user.grant_role!(:helper)

    assert user.has_role?(:helper)
    assert user.helper?
    assert_equal "Helper", user.highest_role

    user.remove_role!(:helper)

    assert_not user.has_role?(:helper)
  end

  test "dismissals mutate array state once" do
    user = users(:one)
    user.update_columns(things_dismissed: [])

    assert user.dismiss_thing!("flagship_ad")
    assert user.has_dismissed?("flagship_ad")
    assert_no_difference -> { user.reload.things_dismissed.count } do
      user.dismiss_thing!("flagship_ad")
    end

    user.undismiss_thing!("flagship_ad")
    assert_not user.reload.has_dismissed?("flagship_ad")
  end

  test "verification payload updates status and ignores nonfatal ineligible responses" do
    user = users(:one)
    user.update!(verification_status: "needs_submission", ysws_eligible: false)

    assert_equal :updated, user.apply_hca_verification_payload!(
      { "verification_status" => "verified", "ysws_eligible" => true },
      persist_with_callbacks: false
    )
    assert user.reload.identity_verified?
    assert user.ysws_eligible?

    assert_equal :ignored_ineligible, user.apply_hca_verification_payload!(
      { "verification_status" => "ineligible", "ysws_eligible" => false, "fatal_rejection" => false },
      persist_with_callbacks: false
    )
    assert user.reload.identity_verified?
  end

  test "manual ysws override wins over stored eligibility" do
    user = users(:one)
    user.update!(ysws_eligible: false, manual_ysws_override: true)

    assert user.ysws_eligible?
  end

  test "balance cache can be invalidated" do
    user = users(:one)

    assert_equal user.ledger_entries.sum(:amount), user.balance

    user.invalidate_balance_cache!

    assert_equal user.balance, user.cached_balance
  end

  test "provider identity lookups use User identity records" do
    user = users(:one)
    User::Identity.insert_all!(
      [
        {
          user_id: user.id,
          provider: "hackatime",
          uid: "hackatime-baseline",
          created_at: Time.current,
          updated_at: Time.current
        }
      ]
    )

    identity = User::Identity.find_by!(provider: "hackatime", uid: "hackatime-baseline")
    assert_equal identity, user.reload.hackatime_identity
    assert_equal user, User.find_by_hackatime("hackatime-baseline")
    assert user.hackatime_identity.present?
  end

  test "grant_email returns hcb_email when present" do
    user = users(:one)
    user.hcb_email = "hcb@example.com"
    assert_equal "hcb@example.com", user.grant_email
  end

  test "grant_email falls back to email when hcb_email is nil" do
    user = users(:one)
    assert user.email.present?, "Fixture user(:one) must have a non-nil email for this test"
    user.hcb_email = nil
    assert_equal user.email, user.grant_email
  end

  test "grant_email falls back to email when hcb_email is blank" do
    user = users(:one)
    user.hcb_email = ""
    assert user.email.present?, "Expected fixture user.email to be present for fallback test"
    assert_equal user.email, user.grant_email
  end

  test "hcb_email validates email format" do
    user = users(:one)
    user.hcb_email = "not-an-email"
    assert_not user.valid?
    assert_includes user.errors[:hcb_email], "is invalid"
    assert_not user.save, "User with invalid hcb_email should not be saved"
  end

  test "hcb_email allows valid email format" do
    user = users(:one)
    user.hcb_email = "valid@example.com"
    assert user.valid?
  end

  test "hcb_email allows blank value" do
    user = users(:one)
    user.hcb_email = ""
    assert user.valid?
  end

  test "hcb_email allows nil value" do
    user = users(:one)
    user.hcb_email = nil
    assert user.valid?
  end

  test "shop_tutorial_needed? requires HCA, a project, and an unfinished walkthrough" do
    user = create_user(slack_id: "U_TUT_NEEDED", display_name: "tutorialneeded")
    refute user.shop_tutorial_needed?, "no project yet"

    project = Project.create!(title: "p", description: "d")
    project.memberships.create!(user: user, role: :owner)
    user.reload

    assert user.shop_tutorial_needed?, "HCA + project + uncompleted = needed"

    user.mark_shop_tutorial_completed!
    refute user.shop_tutorial_needed?, "completed tutorials drop out"
  end

  test "shop_tutorial_needed? is false for guests (no HCA)" do
    user = create_user(slack_id: "U_GUEST", display_name: "guesty", hca_linked: false)
    refute user.shop_tutorial_needed?
  end

  test "mark_shop_tutorial_completed! is idempotent and backfills started_at" do
    user = users(:one)
    user.update_columns(shop_tutorial_started_at: nil, shop_tutorial_completed_at: nil)

    user.mark_shop_tutorial_completed!
    first_completion = user.reload.shop_tutorial_completed_at
    assert first_completion.present?
    assert user.shop_tutorial_started_at.present?

    travel 5.minutes do
      user.mark_shop_tutorial_completed!
      assert_equal first_completion.to_i, user.reload.shop_tutorial_completed_at.to_i,
        "second call should not advance the timestamp"
    end
  end

  test "display_name must be present" do
    user = users(:one)
    user.display_name = ""
    assert_not user.valid?
    assert_includes user.errors[:display_name], "can't be blank"
  end

  test "display_name rejects spaces" do
    user = users(:one)
    user.display_name = "hello world"
    assert_not user.valid?
    assert user.errors[:display_name].any? { |m| m.include?("can only contain") }
  end

  test "display_name rejects unicode and special characters" do
    user = users(:one)
    %w[héllo user@name cool! ñoño 🚀rocket].each do |bad_name|
      user.display_name = bad_name
      assert_not user.valid?, "Expected '#{bad_name}' to be invalid"
    end
  end

  test "display_name allows letters digits hyphens and underscores" do
    user = users(:one)
    %w[hello Hello_World test-user User123 a-b_c].each do |good_name|
      user.display_name = good_name
      assert user.valid?, "Expected '#{good_name}' to be valid but got: #{user.errors.full_messages}"
    end
  end

  test "display_name enforces max length of 30" do
    user = users(:one)
    user.display_name = "a" * 31
    assert_not user.valid?
    assert user.errors[:display_name].any? { |m| m.include?("too long") }
  end

  test "display_name must be unique case-insensitively" do
    user = users(:one)
    other = users(:two)
    other.update_column(:display_name, "TakenName")
    user.display_name = "takenname"
    assert_not user.valid?
    assert user.errors[:display_name].any? { |m| m.include?("taken") }
  end

  test "random_funny_display_name produces safe characters" do
    20.times do
      name = User.random_funny_display_name
      assert_match(/\A[a-zA-Z0-9_-]+\z/, name, "Generated name '#{name}' contains unsafe chars")
      assert name.length <= 30, "Generated name '#{name}' exceeds 30 chars"
    end
  end
end
