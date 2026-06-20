module Admin
  class EmailTemplatesController < Admin::ApplicationController
    before_action :authorize_email_templates
    before_action :set_template, only: [ :destroy ]
    before_action :require_week_2_release

    def index
      @templates = EmailTemplate.order(:name)
    end

    def create
      file = params[:file]
      unless file.respond_to?(:read)
        return redirect_to admin_email_templates_path, alert: "Please select a .mjml file."
      end

      name = params[:name].presence&.strip || File.basename(file.original_filename, ".*").gsub(/\.html$/, "")
      body = file.read.force_encoding("UTF-8")

      template = EmailTemplate.find_or_initialize_by(name: name)
      template.body = body

      if template.save
        redirect_to admin_email_templates_path, notice: "\"#{name}\" #{template.previously_new_record? ? "uploaded" : "updated"}."
      else
        redirect_to admin_email_templates_path, alert: template.errors.full_messages.to_sentence
      end
    end

    def destroy
      @template.destroy
      redirect_to admin_email_templates_path, notice: "\"#{@template.name}\" deleted."
    end

    private

    def set_template
      @template = EmailTemplate.find_by!(name: params[:id])
    end

    def authorize_email_templates
      authorize :admin, :access_email_templates?
    end

    def require_week_2_release
      render_not_found unless Flipper.enabled?(:week_2_release)
    end
  end
end
