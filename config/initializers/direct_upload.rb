Rails.application.config.to_prepare do
  ActiveStorage::DirectUploadsController.class_eval do
    before_action :require_signed_in_uploader

    private

    def require_signed_in_uploader
      return if signed_in_uploader?

      render json: { error: "You must be signed in to upload files." }, status: :unauthorized
    end

    def signed_in_uploader?
      user = User.find_by(id: session[:user_id]) if session[:user_id].present?
      return false if user.nil? || user.banned?

      session[:auth_level] == "hca" || !user.hca_linked?
    end

    alias_method :original_blob_args, :blob_args unless method_defined?(:original_blob_args)

    def blob_args
      # Parse JSON body if Content-Type is JSON and params[:blob] is missing because I'm dumb and I can't figure out what's fucked!
      if request.content_type == "application/json" && params[:blob].blank?
        raw = request.body.read
        request.body.rewind
        parsed = JSON.parse(raw) rescue {}
        parsed = parsed["blob"] if parsed.is_a?(Hash)
        parsed = parsed.symbolize_keys if parsed.is_a?(Hash)
        return parsed if parsed.present?
      end

      original_blob_args
    end
  end
end
