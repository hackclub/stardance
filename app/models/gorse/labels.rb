# frozen_string_literal: true

module Gorse::Labels
  # we need to embedding everntually
  def self.cast(labels)
    labels.compact_blank.transform_values { |value| value == true ? "true" : value }
  end
end
