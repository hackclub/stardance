# The catalog is shared with the browser so dispatch, labels and defaults agree.
class Certification::YswsShortcuts
  CATALOG = JSON.parse(Rails.root.join("config/ysws_shortcuts.json").read).freeze
  MODIFIERS = %w[ctrl alt shift meta].freeze
  KEYS = ("a".."z").to_a + ("0".."9").to_a + %w[equals plus minus underscore question space enter]
  NOTES_MODIFIERS = %w[platform none].freeze
  # These are explicit bindings active outside notes too. Platform-derived
  # Control bindings on Mac are notes-only; other platforms use Alt.
  RESERVED = (
    (%w[a c v x z w r t n l q f p s o] + ("1".."9").to_a).flat_map { |key| [ "ctrl+#{key}", "meta+#{key}" ] } +
    %w[w t n q i j c].flat_map { |key| [ "ctrl+shift+#{key}", "shift+meta+#{key}" ] }
  ).freeze

  def self.bindings(settings)
    CATALOG.transform_values { |action| action.fetch("bindings") }.merge(settings.fetch("bindings", {}))
  end

  def self.errors(settings)
    return [ "Invalid shortcut settings" ] unless settings.is_a?(Hash) && (settings.keys - %w[notes_modifier bindings]).empty?
    return [ "Choose a notes modifier" ] unless NOTES_MODIFIERS.include?(settings.fetch("notes_modifier", "platform"))

    overrides = settings.fetch("bindings", {})
    return [ "Unknown shortcut action" ] unless overrides.is_a?(Hash) && (overrides.keys - CATALOG.keys).empty?

    overrides.each do |action, chords|
      unless chords.is_a?(Array) && chords.length <= 4 && chords.uniq == chords && chords.all? { |chord| valid_chord?(chord) }
        return [ "Invalid bindings for #{CATALOG.fetch(action).fetch('label')} (up to four per action)" ]
      end
      return [ "Complete review needs a modified shortcut" ] if action == "complete" && chords.any? { |chord| !modified?(chord) }
      return [ "That shortcut is reserved by the browser or text editor" ] if (chords & RESERVED).any?
    end

    effective = bindings(settings)
    %w[alt ctrl].each do |platform_modifier|
      modifier = settings.fetch("notes_modifier", "platform")
      modifier = platform_modifier if modifier == "platform"
      [ false, true ].each do |in_notes|
        assigned = {}
        effective.each do |action, chords|
          candidates = if in_notes
            chords.filter_map do |chord|
              if modified?(chord)
                chord
              elsif CATALOG.fetch(action).fetch("notes") && modifier != "none"
                "#{modifier}+#{chord}"
              end
            end
          else
            chords
          end
          candidates.each do |chord|
            if assigned[chord] && assigned[chord] != action
              return [ "#{chord} conflicts with #{CATALOG.fetch(assigned[chord]).fetch('label')}#{' in notes' if in_notes}" ]
            end
            assigned[chord] = action
          end
        end
      end
    end
    []
  end

  def self.modified?(chord)
    (chord.split("+") & %w[ctrl alt meta]).any?
  end

  def self.valid_chord?(chord)
    return false unless chord.is_a?(String) && chord.length <= 40
    parts = chord.split("+", -1)
    key = parts.pop
    KEYS.include?(key) && parts == MODIFIERS.select { |modifier| parts.include?(modifier) } &&
      (!%w[space enter].include?(key) || modified?(chord)) &&
      !(parts.include?("shift") && %w[equals plus minus underscore question].include?(key))
  end
end
