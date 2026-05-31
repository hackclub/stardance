class Api::V1::AmbassadorReferralsController < Api::V1::BaseController
  def index
    render json: referral_payload(Rsvp.ambassador_referrals)
  end

  def show
    if params[:id].to_s.start_with?(Rsvp::AMBASSADOR_REFERRAL_PREFIX)
      render json: referral_payload(Rsvp.ambassador_referrals.where("LOWER(ref) = ?", params[:id].to_s.downcase))
    else
      render json: { error: "Not found" }, status: :not_found
    end
  end

  private
    def referral_payload(referrals)
      referrals = referrals.order(:id)

      {
        prefix: Rsvp::AMBASSADOR_REFERRAL_PREFIX,
        count: referrals.size,
        referrals: referrals.map(&:ambassador_referral_payload)
      }
    end
end
