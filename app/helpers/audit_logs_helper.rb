module AuditLogsHelper
  STANDARD_EVENTS = %w[create update destroy].freeze

  # Returns a descriptive label and CSS class for an audit log version.
  # When an "update" event contains an aasm_state change, we show the
  # new state instead of a generic "update" badge.
  def audit_event_display(version)
    return { label: version.event.to_s.humanize, css_class: version.event } unless version.event == "update"

    changes = parse_version_changes(version)
    aasm = changes["aasm_state"] || changes["ship_status"] || changes["status"]

    if aasm.is_a?(Array) && aasm.length == 2
      new_state = aasm.last.to_s
      { label: new_state.tr("_", " "), css_class: new_state }
    else
      { label: "update", css_class: "update" }
    end
  end

  # Removes duplicate versions caused by PaperTrail auto-tracking + manual
  # Version.create! for the same action. When a custom event and a generic
  # "update" occur within 2 seconds for the same record, the generic one
  # is dropped.
  def dedupe_versions(versions)
    grouped = versions.group_by { |v| [ v.item_type, v.item_id ] }

    duplicates = Set.new
    grouped.each_value do |group|
      group.each_cons(2) do |a, b|
        next unless (a.created_at - b.created_at).abs < 2

        if a.event == "update" && !STANDARD_EVENTS.include?(b.event)
          duplicates << a.id
        elsif b.event == "update" && !STANDARD_EVENTS.include?(a.event)
          duplicates << b.id
        end
      end
    end

    versions.reject { |v| duplicates.include?(v.id) }
  end

  private

  def parse_version_changes(version)
    raw = version.object_changes
    if raw.is_a?(Hash)
      raw
    elsif raw.is_a?(String)
      YAML.safe_load(raw, permitted_classes: [ Time, Date, DateTime, BigDecimal, Symbol ]) rescue {}
    else
      {}
    end
  end
end
