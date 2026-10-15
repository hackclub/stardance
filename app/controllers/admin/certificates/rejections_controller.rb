class Admin::Certificates::RejectionsController < Admin::ApplicationController
  def create
    authorize Certificate, :update?, policy_class: Admin::CertificatePolicy

    certificate = Certificate.pending.find_by(id: params[:certificate_id])
    if certificate.nil?
      redirect_to admin_certificates_path, alert: "That certificate was already reviewed."
    elsif certificate.name != params[:name]
      redirect_to admin_certificates_path,
                  alert: "That request changed to “#{certificate.name}” after you loaded the queue. Review it again."
    else
      certificate.rejected!
      redirect_to admin_certificates_path, notice: "Certificate name “#{certificate.name}” rejected."
    end
  end
end
