class Api::V1::AmbassadorReferralsController < Api::V1::BaseController
  BOOLEAN = ActiveModel::Type::Boolean.new
  private_constant :BOOLEAN

  def index
    render json: payload(User.ambassador_referrals.where(banned: false), rsvp_scope: Rsvp.ambassador_referrals)
  end

  def show
    code = params[:id].to_s
    if code.start_with?(Rsvp::AMBASSADOR_REFERRAL_PREFIX)
      render json: payload(
        User.ambassador_referrals.where(banned: false).matching_ref(code),
        rsvp_scope: Rsvp.ambassador_referrals.matching_ref(code)
      )
    else
      render json: { error: "Not found" }, status: :not_found
    end
  end

  private
    def include_rsvps?
      BOOLEAN.cast(params[:rsvp])
    end

    def payload(scope, rsvp_scope:)
      records = scope.order(:id).to_a
      referrals = user_items(records)
      referrals += rsvp_items(rsvp_scope.order(:id).to_a, referred_users: records) if include_rsvps?

      {
        prefix: Rsvp::AMBASSADOR_REFERRAL_PREFIX,
        count: referrals.size,
        referrals: referrals
      }
    end

    def user_items(users)
      seconds = User.ambassador_referral_seconds(users)

      users.map do |user|
        user.ambassador_referral_payload(
          hours_logged: hours(seconds[:logged][user.id]),
          hours_approved: hours(seconds[:approved][user.id])
        ).merge(rsvp: false)
      end
    end

    def rsvp_items(rsvps, referred_users:)
      referred_emails = referred_users.map { |user| user.email.to_s.downcase }.to_set

      rsvps.reject { |rsvp| referred_emails.include?(rsvp.email.to_s.downcase) }.map do |rsvp|
        rsvp.ambassador_referral_payload.merge(
          rsvp: true,
          slack_id: nil,
          display_name: nil,
          verification_status: nil,
          hours_logged: nil,
          hours_approved: nil
        )
      end
    end

    def hours(seconds)
      ((seconds || 0) / 3600.0).round(2)
    end
end
