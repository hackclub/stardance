class Admin::Users::CertificateCreditsController < Admin::ApplicationController
  def create
    user = User.find(params[:user_id])
    authorize user, :manage_certificate_eligibility?

    credit = params.require(:certificate_credit).permit(:hours, :projects)
    hours = BigDecimal(credit[:hours].to_s)
    projects = Integer(credit[:projects].to_s, 10)
    unless hours.finite? && hours >= 0 && hours == hours.round(2) && projects >= 0
      raise ArgumentError
    end

    user.with_lock do
      user.update!(
        certificate_credit_hours: user.certificate_credit_hours + hours,
        certificate_credit_projects: user.certificate_credit_projects + projects,
        certificate_eligibility_override: true
      )
    end

    redirect_to admin_user_path(user), notice: "Certificate credit added. This user can now claim a certificate."
  rescue ArgumentError
    redirect_to admin_user_path(user), alert: "Enter nonnegative hours (up to two decimal places) and a whole project count."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to admin_user_path(user), alert: error.record.errors.full_messages.to_sentence
  end
end
