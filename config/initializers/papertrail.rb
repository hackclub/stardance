PaperTrail.config.enabled = true
PaperTrail.config.has_paper_trail_defaults = {
  on: %i[create update destroy]
}
PaperTrail.config.version_limit = 500

# Use native JSONB columns - no serializer needed since Rails handles jsonb natively
PaperTrail.serializer = PaperTrail::Serializers::JSON
