# frozen_string_literal: true

# The continuous YSWS review flow: instead of bouncing back to the queue after
# every project, a reviewer starts a session and is carried from one pending
# review to the next until the list runs out.
#
# This is a parallel entry point, never a replacement. Admin::Certification::
# YswsController is untouched — its View link, its Complete Review button and its
# #complete action all still work exactly as they did, and are what every reviewer
# without the ysws_review_flow flag continues to use.
#
# Claiming is deliberately one-at-a-time. Starting a session claims only the first
# project; the rest of the list is a navigation aid, not a reservation, and stays
# available to every other reviewer. A project is claimed as the flow redirects to
# it and released as soon as the reviewer leaves it. YSWS has no
# release_all_for(user) helper, so a design that pre-claimed the list would park
# up to 100 projects behind a 20-minute TTL and starve the other reviewers.
class Admin::Certification::Ysws::FlowController < Admin::Certification::ApplicationController
  include Admin::Certification::YswsFlowHelper

  before_action :require_review_flow
  before_action :set_review, only: [ :skip, :submit ]

  # POST /admin/certification/review/flow
  def create
    authorize ::Certification::Ysws, :update?

    # A session already running resumes where it left off instead of being rebuilt,
    # so a detour back to the queue doesn't cost the reviewer their counters or
    # reinstate the projects they skipped.
    flow = ysws_flow
    if flow.active?
      Rails.logger.info "[YSWS#flow] user=#{current_user&.id} Resuming flow, #{flow.remaining.size} review(s) left"
      return advance_to(flow.remaining)
    end

    ids = queue_ids
    if ids.empty?
      return redirect_to admin_certification_ysws_reviews_path,
                         notice: "Nothing in the queue to review right now."
    end

    store_flow(ids: ids, skipped: [], projects: 0, devlogs: 0)
    Rails.logger.info "[YSWS#flow] user=#{current_user&.id} Started flow with #{ids.size} review(s)"

    advance_to(ids)
  end

  # GET /admin/certification/review/:id/flow/next
  def next
    authorize ::Certification::Ysws, :update?

    flow = ysws_flow
    unless flow.active?
      return redirect_to admin_certification_ysws_reviews_path,
                         notice: "No review session is running."
    end

    advance_to(flow.remaining_after(params[:id].to_i))
  end

  # POST /admin/certification/review/:id/flow/skip
  def skip
    authorize @review, :update?

    flow = ysws_flow
    unless flow_review?(flow, @review)
      return redirect_to admin_certification_ysws_reviews_path,
                         alert: flow_review_error
    end

    # Only ever drop our own claim. The policy's :update? is queue-wide, so
    # without this a reviewer could hand back a project another admin is holding.
    released = @review.claimed_by?(current_user) && @review.release_claim!

    store_flow(ids: flow.ids, skipped: flow.skipped | [ @review.id ],
               projects: flow.projects, devlogs: flow.devlogs)
    Rails.logger.info "[YSWS#flow] user=#{current_user&.id} review=#{@review.id} Skipped; claim_released=#{!!released}"

    redirect_to admin_certification_ysws_flow_next_path(@review.id)
  end

  # POST /admin/certification/review/:id/flow/submit
  def submit
    authorize @review, :update?

    flow = ysws_flow
    unless flow_review?(flow, @review)
      return render json: { success: false, error: flow_review_error }, status: :unprocessable_entity
    end

    # A submit that already landed must never land twice. sync_to_airtable_inline
    # holds the request open for a full Airtable round trip, so a proxy timeout or
    # a dropped connection can hand the reviewer a failure for work the server has
    # already committed — and the button re-arms on that path. Re-completing would
    # re-stamp reviewed_at into a fresh leaderboard week and count the project
    # twice in the session tally. completion_blocker can't catch this: in_unified_db
    # is filled in by an Airtable automation and is still blank during the retry
    # window. Answering success carries a genuine duplicate on to the next project.
    return render json: already_completed_payload if @review.reviewed_at?

    unless @review.pending?
      return render json: { success: false, error: "This review is no longer pending." },
                    status: :unprocessable_entity
    end

    unless claimed_for_flow_submit?(@review)
      return render json: { success: false, error: "This review is no longer claimed by you." },
                    status: :conflict
    end

    if (blocker = completion_blocker(@review))
      Rails.logger.warn "[YSWS#flow] user=#{current_user&.id} review=#{@review.id} Blocked: #{blocker}"
      return render json: { success: false, error: blocker }, status: :unprocessable_entity
    end

    devlog_count = @review.devlog_reviews.size
    complete_review!(@review)
    record_completion(devlog_count)
    Rails.logger.info "[YSWS#flow] user=#{current_user&.id} review=#{@review.id} " \
                      "Marked reviewed_at=#{@review.reviewed_at}; syncing to Airtable inline"

    sync_to_airtable_inline
  rescue Pundit::NotAuthorizedError
    raise
  rescue StandardError => e
    Rails.logger.error "[YSWS#flow] user=#{current_user&.id} review=#{params[:id]} #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
    Sentry.capture_exception(e, tags: { category: "certification.ysws" }, extra: { ysws_review_id: params[:id], user_id: current_user&.id })
    render json: { success: false, error: "Failed to submit review: #{e.message}. Let AVD know!" },
           status: :unprocessable_entity
  end

  # DELETE /admin/certification/review/flow
  def destroy
    review = ::Certification::Ysws.find_by(id: params[:review_id])
    review ? authorize(review, :update?) : authorize(::Certification::Ysws, :update?)

    review.release_claim! if review&.claimed_by?(current_user)
    end_flow("ended")
  end

  private

  # Behind a flag so the flow can be rolled out per reviewer — and pulled back
  # without a deploy, which drops everyone straight onto the untouched queue path.
  # A before_action that redirects halts the callback chain, so Pundit's
  # verify_authorized never runs on this path.
  def require_review_flow
    return if ysws_flow_enabled?

    # Drain a session left behind by a reviewer who had the flag pulled
    # mid-flow. Without this their cookie would outlive the flag and every flow
    # endpoint would keep bouncing them here.
    session.delete(SESSION_KEY)
    redirect_to admin_certification_ysws_reviews_path,
                alert: "The continuous review flow isn't enabled for your account."
  end

  def set_review
    @review = ::Certification::Ysws.includes(:devlog_reviews).find(params[:id])
  end

  def flow_review?(flow, review)
    flow.active? && flow.position(review.id).present?
  end

  def flow_review_error
    "That review is not part of your active review session."
  end

  def claimed_for_flow_submit?(review)
    return true if review.claimed_by?(current_user)

    ::Certification::Ysws.atomic_claim!(review.id, current_user).present?
  end

  # ---- Navigation ------------------------------------------------------------

  # Walks `candidates` in order and sends the reviewer to the first one that is
  # still reviewable, claiming exactly that one on the way. Anything completed,
  # returned, deleted, or picked up by another admin since the list was built is
  # stepped over. One query establishes what is available; the claim is only
  # attempted on candidates that survived it, so the common case is a single
  # extra write.
  def advance_to(candidates)
    return end_flow("finished") if candidates.empty?

    available = ::Certification::Ysws
      .pending
      .unclaimed_or_claimed_by(current_user)
      .where(id: candidates)
      .pluck(:id)
      .to_set

    candidates.each do |id|
      next unless available.include?(id)
      next unless ::Certification::Ysws.atomic_claim!(id, current_user)

      return redirect_to admin_certification_ysws_review_path(id)
    end

    end_flow("finished", held_elsewhere: ::Certification::Ysws.pending.where(id: candidates).count)
  end

  # Clears the session and reports what the reviewer got through. `held_elsewhere`
  # separates the two ways a list runs dry: genuinely finished, or the tail of it
  # is sitting in someone else's claim and will come back later.
  def end_flow(verb, held_elsewhere: 0)
    flow = ysws_flow
    session.delete(SESSION_KEY)
    Rails.logger.info "[YSWS#flow] user=#{current_user&.id} Flow #{verb}; " \
                      "projects=#{flow.projects} devlogs=#{flow.devlogs} held_elsewhere=#{held_elsewhere}"

    redirect_to admin_certification_ysws_reviews_path, notice: flow_summary(verb, flow, held_elsewhere)
  end

  def flow_summary(verb, flow, held_elsewhere)
    summary =
      if flow.projects.zero?
        "Review session #{verb}."
      else
        "Review session #{verb} — #{helpers.pluralize(flow.projects, 'project')} and " \
          "#{helpers.pluralize(flow.devlogs, 'devlog')} reviewed."
      end
    return summary if held_elsewhere.zero?

    "#{summary} #{helpers.pluralize(held_elsewhere, 'review')} left in it " \
      "#{held_elsewhere == 1 ? 'is' : 'are'} claimed by another reviewer right now."
  end

  # Shaped like a fresh submit so the JS needs no extra branch: synced reviews
  # move straight on, unsynced ones stop and point at Resync exactly as they would
  # have the first time.
  def already_completed_payload
    Rails.logger.info "[YSWS#flow] user=#{current_user&.id} review=#{@review.id} " \
                      "Already completed at #{@review.reviewed_at}; treating the resubmit as a no-op"
    synced = @review.airtable_synced_at.present?

    {
      success: true,
      synced: synced,
      error: ("Airtable didn't confirm the sync. Use Resync on this review before moving on." unless synced)
    }.compact
  end

  # ---- Session ---------------------------------------------------------------

  # The whole session cookie is capped at 4096 bytes and the flow is only one of
  # the things living in it, so the id list is capped at MAX_IDS. That cap is the
  # entire protection, and it has to be: CookieOverflow is raised by the cookie
  # middleware as the response is committed, never by this assignment, so there is
  # nothing catchable here. 100 ids is well under a kilobyte.
  def store_flow(ids:, skipped:, projects:, devlogs:)
    session[SESSION_KEY] = {
      "ids" => ids.first(MAX_IDS), "skipped" => skipped, "projects" => projects, "devlogs" => devlogs
    }
  end

  # Credit is counted per completed project, matching how the leaderboard
  # attributes devlogs: they land on a reviewer once their parent review is
  # marked reviewed. Skipped work deliberately counts for nothing.
  def record_completion(devlog_count)
    flow = ysws_flow
    return unless flow.active?

    store_flow(ids: flow.ids, skipped: flow.skipped,
               projects: flow.projects + 1, devlogs: flow.devlogs + devlog_count)
  end

  # ---- Completion ------------------------------------------------------------

  # SECOND COPY of the completion rules in Admin::Certification::YswsController
  # #complete. Kept separate on purpose so this addon cannot disturb the queue's
  # own Complete Review button — if you change the rules there, change them here
  # too. Returns the reviewer-facing reason, or nil when the review may be closed.
  def completion_blocker(review)
    review.check_and_update_unified_db_status!
    return "This review is already in the unified DB" if review.in_unified_db.present?

    devlog_reviews = review.devlog_reviews
    return "Review all devlogs before completing." if devlog_reviews.any?(&:pending?)

    approved = devlog_reviews.select(&:approved?)
    if approved.any? && approved.none? { |dr| dr.justification.present? }
      return "Add a justification to at least one approved devlog."
    end

    return "Add a justification to every rejected devlog." if devlog_reviews.any? { |dr| dr.rejected? && dr.justification.blank? }

    nil
  end

  # save! rather than #complete's update_columns, so PaperTrail records who closed
  # the review (whodunnit is set in Admin::ApplicationController) — CLAUDE.md wants
  # an audit trail on admin mutations. validate: false keeps parity with
  # update_columns: the flow must never refuse a review the queue's own button
  # would have accepted, and PaperTrail's callback still fires either way.
  #
  # Dropping the claim mirrors Certification::YswsReviewRejector, which already
  # makes this exact transition.
  def complete_review!(review)
    review.assign_attributes(
      reviewer_id: current_user.id,
      reviewed_at: Time.current,
      claimed_by_id: nil,
      claimed_at: nil
    )
    review.save!(validate: false)
  end

  # DELIBERATELY INLINE — do not "optimise" this back to perform_later.
  #
  # The flow's submit button tells the reviewer "Synced ✓" before moving on, and
  # that is only honest if the Airtable write has already happened. The queue's own
  # #complete keeps its background perform_later; only the flow waits.
  #
  # A failed sync does not mean the review is unreviewed — reviewed_at was stamped
  # before this ran — so the recovery path is the existing Resync action, never
  # completing the review a second time. The job stamps airtable_synced_at as its
  # last step, so that column (not merely "perform_now didn't raise") is what
  # decides whether the sync landed: the job's own retry_on/discard_on handlers can
  # swallow a failure and quietly re-enqueue instead of raising here.
  def sync_to_airtable_inline
    synced_before = @review.airtable_synced_at

    ::Certification::YswsAirtableSyncJob.perform_now(@review.id)

    if @review.reload.airtable_synced_at.present? && @review.airtable_synced_at != synced_before
      render json: { success: true, synced: true }
    else
      Rails.logger.warn "[YSWS#flow] user=#{current_user&.id} review=#{@review.id} Airtable sync did not confirm"
      render json: {
        success: true, synced: false,
        error: "Airtable didn't confirm the sync. Use Resync on the review page."
      }
    end
  rescue StandardError => e
    Rails.logger.error "[YSWS#flow] user=#{current_user&.id} review=#{@review.id} Airtable sync failed: #{e.class}: #{e.message}"
    Sentry.capture_exception(e, tags: { category: "certification.ysws" }, extra: { ysws_review_id: @review.id, user_id: current_user&.id })
    render json: { success: true, synced: false, error: e.message }
  end

  # ---- Queue -----------------------------------------------------------------

  # SECOND COPY of the queue query in Admin::Certification::YswsController#index.
  # Kept separate on purpose so this addon cannot disturb the queue page — if you
  # change the filtering or ordering there, change it here too, or the flow will
  # quietly walk the projects in a different order than the table shows.
  def queue_ids
    filters        = saved_filters
    project_type   = filters["project_type"].presence
    sort           = filters["sort"].presence_in(%w[length todo])
    dir            = filters["dir"] == "asc" ? "asc" : "desc"
    with_integrity = filters["with_integrity"] != "0"

    scope = ::Certification::Ysws.pending.unclaimed_or_claimed_by(current_user)
    scope = scope.with_integrity_check if with_integrity
    scope = scope.by_project_type(project_type) if project_type
    scope = scope.with_todo_devlog_count

    scope =
      case sort
      when "length" then scope.order(Arel.sql("certification_ysws_reviews.original_minutes #{dir}"))
      when "todo"   then scope.order(Arel.sql("todo_devlog_count #{dir}"))
      else               scope.order(created_at: :asc)
      end

    # LIMIT in SQL, not .first(MAX_IDS) in Ruby: the pending queue can run to
    # thousands of rows and there is no reason to instantiate all of them to keep
    # the first hundred.
    #
    # .map(&:id) rather than .pluck(:id): pluck replaces the scope's select list,
    # which drops the todo_devlog_count alias that the "todo" sort orders by.
    scope.limit(MAX_IDS).map(&:id)
  end

  # The reviewer's saved queue filters, read straight out of the session rather
  # than through YswsController#index's merge block: that block starts from an
  # empty hash whenever a filter param is present, so re-entering it here would be
  # a way to silently blank a reviewer's saved filters.
  def saved_filters
    session[Admin::Certification::YswsController::FILTER_SESSION_KEY]
      .to_h.slice("project_type", "sort", "dir", "with_integrity")
  end
end
