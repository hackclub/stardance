class CertificatesController < ApplicationController
  def show
    skip_authorization

    @approved_hours = current_user.approved_hours if current_user && current_user.certificate.nil?

    @code = Certificate.normalize_code(params[:code]) if params[:code].present?
    return if @code.blank?

    @certificate = Certificate.approved.find_by(code: @code)
    @projects = approved_projects_for(@certificate.user) if @certificate
  end

  def create
    authorize Certificate

    certificate = current_user.build_certificate(hours_at_issue: current_user.approved_hours)
    request_and_redirect(certificate)
  end

  def update
    certificate = current_user&.certificate
    return render_not_found if certificate.nil?

    authorize certificate
    certificate.hours_at_issue = current_user.approved_hours
    request_and_redirect(certificate)
  end

  def regenerate
    certificate = current_user&.certificate
    return render_not_found if certificate.nil?

    authorize certificate
    certificate.hours_at_issue = current_user.approved_hours
    request_and_redirect(certificate)
  end

  def download
    authorize Certificate, :download?

    certificate = current_user.certificate
    send_data Certificate::Pdf.new(certificate).render,
              type: "application/pdf",
              disposition: "attachment",
              filename: "stardance-certificate-#{certificate.code}.pdf"
  end

  private

  def certificate_params
    params.fetch(:certificate, {}).permit(:name)
  end

  def requested_name
    certificate_params[:name].presence || current_user.full_name
  end

  def request_and_redirect(certificate)
    if certificate.request_with(requested_name)
      notice = if certificate.approved?
        "Your certificate has been issued!"
      else
        "Certificate requested! Custom names get a quick review before they're issued."
      end
      redirect_to certificate_path, notice: notice
    else
      redirect_to certificate_path, alert: certificate.errors.full_messages.to_sentence
    end
  rescue ActiveRecord::RecordNotUnique
    redirect_to certificate_path, notice: "Your certificate request was already received."
  end

  def approved_projects_for(user)
    Project.where(id: Post.approved_ship_events_by(user).select(:project_id))
           .includes(banner_attachment: :blob, mission_attachments: { mission: { banner_attachment: :blob } })
           .order(created_at: :desc)
  end
end
