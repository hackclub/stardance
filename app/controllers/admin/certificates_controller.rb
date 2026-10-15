class Admin::CertificatesController < Admin::ApplicationController
  def index
    authorize Certificate, policy_class: Admin::CertificatePolicy

    @pending = Certificate.pending.includes(:user).order(created_at: :asc)
    @reviewed = Certificate.where.not(status: "pending").includes(:user).order(updated_at: :desc).limit(25)
  end
end
