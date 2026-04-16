class Api::V1::DocsController < ActionController::Base
  def index
    spec = YAML.safe_load_file(Rails.root.join("docs/openapi.yml"), aliases: true) || {}
    escaped_spec_json = ERB::Util.json_escape(spec.to_json)

    render html: <<~HTML.html_safe
      <!doctype html>
      <html>
        <head>
          <title>Stardance API Reference</title>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
        </head>
        <body>
          <div id="app"></div>
          <script src="https://cdn.jsdelivr.net/npm/@scalar/api-reference"></script>
          <script>
            Scalar.createApiReference('#app', {
              spec: { content: #{escaped_spec_json} },
              theme: 'purple',
              hideClientButton: true,
              hideDarkModeToggle: true,
              showDeveloperTools: 'never',
              agent: { disabled: true }
            })
          </script>
        </body>
      </html>
    HTML
  end
end
