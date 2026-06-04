# Async wrapper around LookoutHeartbeatForwarder. The recorder forwards
# synchronously now (so it can show the user a real error), but this stays for
# any background/retry enqueues. The forwarder owns the actual logic and result.
class ForwardLookoutHeartbeatsJob < ApplicationJob
  queue_as :default

  def perform(lookout_session_id, project_name = nil)
    session = LookoutSession.find_by(id: lookout_session_id)
    return unless session

    LookoutHeartbeatForwarder.call(session, project_name: project_name)
  end
end
