mjml_path = Rails.root.join("node_modules/.bin/mjml")

if mjml_path.exist?
  Mjml.setup do |config|
    config.mjml_binary = mjml_path.to_s
  end
else
  Rails.logger.warn "[MJML] Binary not found at #{mjml_path} — email template rendering will be unavailable. Run `npm install` to fix this."
end
