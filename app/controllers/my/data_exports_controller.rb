class My::DataExportsController < ApplicationController
  before_action :authenticate_user!

  def index
    authorize :my, :show_data_exports?

    @body_class = "app-layout-page"
    @data_exports = current_user.data_exports.retained.order(created_at: :desc).limit(20)
  end

  def create
    authorize :my, :create_data_export?

    current_user.data_exports.stale_active.update_all(
      status: "failed",
      error_message: "Export generation timed out. Please request a new export.",
      updated_at: Time.current
    )

    active_export = current_user.data_exports.pending_or_processing.last
    if active_export
      redirect_to my_data_exports_path, notice: "An export is already in progress. Please wait for it to complete."
      return
    end

    data_export = current_user.data_exports.create!(status: "pending")
    unless User::DataExportJob.perform_later(data_export.id)
      data_export.update!(
        status: "failed",
        error_message: "The export could not be queued. Please try again."
      )
      redirect_to my_data_exports_path, alert: "Your data export could not be queued. Please try again."
      return
    end

    redirect_to my_data_exports_path, notice: "Your data export has been queued. You'll be able to download it once it's ready."
  rescue ActiveRecord::RecordNotUnique
    # The partial unique index on (user_id) WHERE status IN ('pending',
    # 'processing') backs the check above at the DB level; a concurrent
    # request lands here instead of double-queuing.
    redirect_to my_data_exports_path, notice: "An export is already in progress. Please wait for it to complete."
  end

  def show
    data_export = current_user.data_exports.find(params[:id])
    authorize :my, :download_data_export?

    if data_export.expired?
      redirect_to my_data_exports_path, alert: "This export has expired and is no longer available."
      return
    end

    unless data_export.download_available?
      redirect_to my_data_exports_path, alert: "This export is not ready for download."
      return
    end

    redirect_to rails_blob_path(data_export.zip_file, disposition: "attachment")
  end

  def destroy
    data_export = current_user.data_exports.find(params[:id])
    authorize :my, :destroy_data_export?

    data_export.destroy!
    redirect_to my_data_exports_path, notice: "Your data export has been deleted."
  end

  private

  def authenticate_user!
    return if current_user.present?

    store_return_to
    redirect_to root_path, alert: "Please sign in to continue."
  end
end
