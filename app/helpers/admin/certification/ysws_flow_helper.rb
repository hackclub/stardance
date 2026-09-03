# frozen_string_literal: true

# Reads the continuous-review-flow session written by
# Admin::Certification::Ysws::FlowController, so the controller and the YSWS
# admin views (the queue's Start/Resume button, the sticky session bar) share one
# definition of the session key and its shape instead of parsing it twice.
#
# The session stores nothing but the ordered review ids, the ids passed over, and
# two running counters. The reviewer's *position* is never stored — it is derived
# from where the review they are looking at sits in that list, so a refresh or the
# browser's Back button cannot desynchronise it.
module Admin::Certification::YswsFlowHelper
  SESSION_KEY = :admin_ysws_flow

  # The whole session cookie is capped at 4096 bytes (config/application.rb) and
  # the flow is only one of the things living in it, so a session carries at most
  # this many ids. A reviewer who clears 100 projects in one sitting starts a
  # second session.
  MAX_IDS = 100

  Flow = Struct.new(:ids, :skipped, :projects, :devlogs, keyword_init: true) do
    def active?
      ids.any?
    end

    def total
      ids.size
    end

    # 1-based position of a review within the session list, or nil when the
    # review isn't part of it — reached through a "prior reviews" history link,
    # say, which must not render a bogus "0 of 24".
    def position(review_id)
      index = ids.index(review_id)
      index && index + 1
    end

    # The whole list bar anything skipped. Completed reviews stay in it — they no
    # longer match the pending scope, so a walk steps straight over them, and
    # leaving them keeps every position in the session bar stable.
    def remaining
      ids - skipped
    end

    # Everything after `review_id`, minus anything skipped. A review that isn't in
    # the list falls back to the whole of it: everything ahead has already been
    # decided, so no completed review is ever revisited.
    def remaining_after(review_id)
      index = ids.index(review_id)
      index ? ids.drop(index + 1) - skipped : remaining
    end
  end

  EMPTY = Flow.new(ids: [].freeze, skipped: [].freeze, projects: 0, devlogs: 0).freeze

  class << self
    # Tolerates both session serialisations: string keys after a cookie round
    # trip, symbol keys when read back in the request that wrote them. Anything
    # unrecognisable reads as an inactive flow rather than raising.
    def parse(raw)
      return EMPTY unless raw.is_a?(Hash)

      Flow.new(
        ids: ids_at(raw, "ids"),
        skipped: ids_at(raw, "skipped"),
        projects: at(raw, "projects").to_i,
        devlogs: at(raw, "devlogs").to_i
      )
    end

    private

    def at(raw, key)
      raw.key?(key) ? raw[key] : raw[key.to_sym]
    end

    def ids_at(raw, key)
      Array(at(raw, key)).filter_map { |id| Integer(id, exception: false) }
    end
  end

  def ysws_flow_enabled?
    Flipper.enabled?(:ysws_review_flow, current_user)
  end

  # The current reviewer's flow session. Safe to call from any YSWS admin view.
  #
  # Reads as inactive whenever the flag is off, which is the single gate the
  # views rely on: a session cookie outlives the flag being pulled, and without
  # this a reviewer caught mid-flow would keep being shown a session bar and a
  # "Complete & next" button whose every endpoint now redirects them away.
  def ysws_flow
    return EMPTY unless ysws_flow_enabled?

    Admin::Certification::YswsFlowHelper.parse(session[SESSION_KEY])
  end
end
