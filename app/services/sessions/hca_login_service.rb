module Sessions
  class HCALoginService
    Result = Struct.new(:status, :user, :is_new_user, :guest_collision, :alert, keyword_init: true) do
      def ok? = status == :ok
    end

    def initialize(auth:, current_user:, referral_code: nil)
      @auth = auth
      @current_user = current_user
      @referral_code = referral_code
    end

    def call
      return invalid_provider_result unless valid_provider?

      identity_data = HCAService.identity(access_token)
      if identity_data.blank?
        Sentry.capture_message("Authentication failed: unable to fetch identity data", level: :warning)
        return fail_result(:missing_identity, "Authentication failed")
      end

      fields = extract_identity_fields(identity_data)
      return fail_result(:missing_uid, "Your Hack Club account is broken. Please contact support.") if fields[:uid].blank?
      return fail_result(:missing_slack_id, "Your Hack Club account is not linked to a Slack account! Please contact support.") if fields[:slack_id].blank?
      return fail_result(:invalid_verification, "Your Hack Club account is broken. Please contact support.") unless User.verification_statuses.key?(fields[:verification_status])

      identity = User::Identity.find_or_initialize_by(provider: "hack_club", uid: fields[:uid])
      user = identity.user || User.find_by(slack_id: fields[:slack_id]) || guest_to_upgrade || User.new

      guest_collision = guest_to_upgrade.present? && user.persisted? && user.id != guest_to_upgrade.id

      identity = resolve_uid_change(identity, user, fields[:slack_id], fields[:uid])
      identity.access_token = access_token

      is_new_user = user.new_record?
      assign_user_attributes(user, fields, is_new_user)

      begin
        user.save!
      rescue ActiveRecord::RecordInvalid => e
        Sentry.capture_exception(e, extra: {
          user_id: user.id, user_errors: user.errors.full_messages,
          slack_id: fields[:slack_id], uid: fields[:uid], is_new_user: is_new_user
        })
        return fail_result(:user_save_failed, "Unable to save your account. Please contact support.")
      end

      identity.user = user
      begin
        identity.save!
      rescue ActiveRecord::RecordInvalid => e
        Sentry.capture_exception(e, extra: {
          identity_id: identity.id, identity_errors: identity.errors.full_messages,
          user_id: user.id, provider: identity.provider, uid: identity.uid,
          existing_identity_for_user: user.identities.find_by(provider: "hack_club")
                                           &.attributes&.except("access_token_ciphertext", "refresh_token_ciphertext")
        })
        return fail_result(:identity_save_failed, "Unable to link your Hack Club account. Please contact support.")
      end

      user.apply_hca_verification_payload!(identity_data)

      if user.age_attestation_teen_13_18? && hca_birthday_contradicts_teen?(identity_data)
        user.update!(age_attestation: "ineligible")
        identity.destroy
        Sentry.capture_message(
          "HCA birthday contradicts teen attestation; identity removed",
          level: :warning,
          extra: { user_id: user.id, hca_birthday: identity_data["birthday"], slack_id: fields[:slack_id] }
        )
        return Result.new(
          status: :age_violation,
          user: user,
          is_new_user: is_new_user,
          guest_collision: false,
          alert: "We weren't able to verify your age. Please try again later."
        )
      end

      Result.new(
        status: :ok,
        user: user,
        is_new_user: is_new_user,
        guest_collision: guest_collision,
        alert: nil
      )
    end

    private

    attr_reader :auth, :current_user, :referral_code

    def access_token = auth.credentials&.token.to_s

    def guest_to_upgrade
      @guest_to_upgrade ||= current_user if current_user&.guest?
    end

    def valid_provider?
      # provider is a symbol. do not change it to string... equality will fail otherwise
      auth.provider == :hack_club && (current_user.blank? || current_user.guest?)
    end

    def invalid_provider_result
      Sentry.capture_message(
        "Authentication failed: invalid provider or user already signed in",
        level: :warning,
        extra: { provider: auth.provider, user_signed_in: current_user.present? }
      )
      fail_result(:invalid_provider, "Authentication failed or user already signed in")
    end

    def fail_result(status, alert)
      Result.new(status: status, alert: alert, user: nil, is_new_user: false, guest_collision: false)
    end

    def extract_identity_fields(data)
      {
        email:               data["primary_email"].presence.to_s,
        first_name:          data["first_name"].to_s.strip,
        last_name:           data["last_name"].to_s.strip,
        verification_status: data["verification_status"].to_s,
        ysws_eligible:       data["ysws_eligible"] == true,
        slack_id:            data["slack_id"].to_s,
        uid:                 data["id"].to_s
      }
    end

    def resolve_uid_change(identity, user, slack_id, uid)
      return identity unless identity.new_record? && user.persisted?

      existing_identity = user.identities.find_by(provider: "hack_club")
      return identity unless existing_identity

      Sentry.capture_message(
        "User UID changed on HCA side",
        level: :info,
        extra: { user_id: user.id, old_uid: existing_identity.uid, new_uid: uid, slack_id: slack_id }
      )
      existing_identity.uid = uid
      existing_identity
    end

    def assign_user_attributes(user, fields, is_new_user)
      user.email ||= fields[:email]
      user.display_name = User.random_funny_display_name if user.display_name.to_s.strip.blank?
      user.first_name = fields[:first_name] if fields[:first_name].present?
      user.last_name = fields[:last_name] if fields[:last_name].present?
      user.slack_id = fields[:slack_id] if user.slack_id.to_s != fields[:slack_id]

      if is_new_user && referral_code.present? && referral_code.length <= 64
        user.ref = referral_code
      end
    end

    def hca_birthday_contradicts_teen?(identity_data)
      birthday_str = identity_data["birthday"].to_s
      return false if birthday_str.blank?

      birthday = Date.parse(birthday_str) rescue nil
      return false if birthday.nil?

      today = Date.current
      age = today.year - birthday.year
      age -= 1 if today < birthday + age.years
      age < 13 || age > 18
    end
  end
end
