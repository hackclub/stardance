# frozen_string_literal: true

# Reports a condition that isn't an exception (e.g. "poller is failing most
# decisions") through Rails.error, which AppSignal subscribes to.
class OperationalAlert < StandardError
  def self.report(message, severity: :warning, context: {})
    Rails.error.report(new(message), handled: true, severity: severity, context: context)
  end
end
