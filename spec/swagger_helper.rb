# frozen_string_literal: true

require 'rails_helper'
require 'yaml'

RSpec.configure do |config|
  config.openapi_root = Rails.root.join('docs').to_s

  existing_openapi =
    if File.exist?(Rails.root.join('docs/openapi.yml'))
      YAML.safe_load_file(Rails.root.join('docs/openapi.yml'), aliases: true) || {}
    else
      {}
    end

  config.openapi_specs = {
    'openapi.yml' => {
      openapi: existing_openapi.fetch('openapi', '3.0.3'),
      info: existing_openapi.fetch('info', {
        'title' => 'Stardance API',
        'version' => 'v1',
        'description' => 'You need an API key to use this! Go to your [account settings](https://flavortown.hackclub.com/kitchen?settings=1) to get one.'
      }),
      servers: existing_openapi.fetch('servers', [
        { 'url' => 'https://flavortown.hackclub.com/api/v1' }
      ]),
      security: existing_openapi.fetch('security', [
        { 'bearerAuth' => [] }
      ]),
      components: existing_openapi.fetch('components', {}),
      paths: {}
    }
  }

  config.openapi_format = :yaml
end
