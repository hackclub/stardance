class Api::V1::AmbassadorReferralsController < Api::V1::BaseController
  BOOLEAN = ActiveModel::Type::Boolean.new
  private_constant :BOOLEAN

  def index
    render json: payload(User.ambassador_referrals, rsvp_scope: Rsvp.ambassador_referrals)
  end

  def show
    code = params[:id].to_s
    if code.start_with?(Rsvp::AMBASSADOR_REFERRAL_PREFIX)
      render json: payload(
        User.ambassador_referrals.matching_ref(code),
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
      referrals += rsvp_items(rsvp_scope.order(:id).to_a) if include_rsvps?

      {
        prefix: Rsvp::AMBASSADOR_REFERRAL_PREFIX,
        count: referrals.size,
        referrals: referrals
      }
    end

    def user_items(users)
      metrics = AmbassadorReferralMetrics.new(users)

      users.map do |user|
        user.ambassador_referral_payload(
          hours_logged: hours(metrics.logged_seconds[user.id]),
          hours_approved: hours(metrics.approved_seconds[user.id])
        ).merge(rsvp: false)
      end
    end

    def rsvp_items(rsvps)
      users_by_email = User.matching_emails(rsvps.map(&:email))
                           .index_by { |user| user.email.to_s.downcase }

      rsvps.reject { |rsvp| users_by_email.key?(rsvp.email.to_s.downcase) }.map do |rsvp|
        rsvp.ambassador_referral_payload.merge(
          rsvp: true,
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
