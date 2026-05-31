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
              hideClientButton: true,
              theme: 'kepler',
              showDeveloperTools: 'never',
              agent: { disabled: true },
              customCss: '.scalar-mcp-layer { display: none !important; } main { background: #0b0920; }'
            })
          </script>
        </body>
      </html>
    HTML
  end
end
