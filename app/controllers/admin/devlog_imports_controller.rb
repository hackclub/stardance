module Admin
  class DevlogImportsController < Admin::ApplicationController
    def new
      authorize :admin, :import_devlogs?
    end

    def create
      authorize :admin, :import_devlogs?

      json_input = params[:devlog_json].to_s.strip
      if json_input.blank?
        flash.now[:alert] = "JSON input is required"
        return render :new, status: :unprocessable_entity
      end

      dry_run = params[:dry_run] == "1"
      service = DevlogImportService.new(json_input, dry_run: dry_run)
      result = service.call

      if result.success?
        if dry_run
          flash[:notice] = "Dry run passed — JSON is valid and all images are reachable."
        else
          flash[:notice] = "Created #{result.devlogs.size} devlog(s) successfully."
        end
        redirect_to new_admin_devlog_import_path
      else
        flash.now[:alert] = result.errors.join("\n")
        @json_input = json_input
        render :new, status: :unprocessable_entity
      end
    end
  end
end
