# frozen_string_literal: true

# Clears out YSWS reviews whose project has been soft-deleted.
#
# Banning a user soft-deletes every project they own, which also stamps
# deleted_at on all of that project's devlogs. The YSWS review and its devlog
# reviews survive, so they stay in the reviewer queue pointing at content no
# reviewer can judge — and the review page itself blows up as soon as a devlog
# review's post_devlog is scoped out. Projects deleted by their own maker leave
# the same residue, so this covers every soft-deleted project, banned or not.
#
# Certification::YswsReviewRejector does the work: every devlog review is
# rejected (0 approved minutes, justification "banned" / "project deleted"), the
# review is stamped reviewed_at with AVD as the reviewer, and the Airtable sync
# is enqueued so the unified YSWS base gets the rejection. Reviews whose ship
# event has no integrity check are left unsynced — the sync job raises on those
# — and reported separately.
#
# DRY RUN BY DEFAULT: logs and returns the candidate ids and writes nothing.
# Pass dry_run: false to persist.
#
# Usage:
#   OneTime::RejectDeletedProjectYswsReviewsJob.perform_now                  # dry run
#   OneTime::RejectDeletedProjectYswsReviewsJob.perform_now(dry_run: false)  # writes
class OneTime::RejectDeletedProjectYswsReviewsJob < ApplicationJob
  queue_as :literally_whenever

  LOG_PREFIX = "[RejectDeletedProjectYswsReviews]"

  # Pending reviews sitting on a soft-deleted project.
  #
  # Project.deleted can't be used here: SoftDeletable's default scope still
  # applies on top of it and cancels it out, so the deleted set has to come
  # through with_deleted.
  def scope
    ::Certification::Ysws.pending
      .where(project_id: ::Project.with_deleted.where.not(deleted_at: nil).select(:id))
  end

  def perform(dry_run: true)
    reviews = scope.includes(:user, :devlog_reviews).to_a

    if dry_run
      banned = reviews.count { |review| review.user.banned? }
      Rails.logger.info "#{LOG_PREFIX} DRY RUN — would reject #{reviews.size} review(s) " \
                        "(#{banned} from banned users): #{reviews.map(&:id).inspect}"
      return reviews.map(&:id)
    end

    summary = { reviews: 0, devlog_reviews: 0, synced: 0, sync_skipped: 0 }

    reviews.each do |review|
      reason = review.user.banned? ? :banned : :project_deleted
      result = ::Certification::YswsReviewRejector.new(review, reason: reason).call
      next unless result.rejected

      summary[:reviews]        += 1
      summary[:devlog_reviews] += result.devlog_reviews
      result.synced ? summary[:synced] += 1 : summary[:sync_skipped] += 1
    end

    Rails.logger.info "#{LOG_PREFIX} Rejected #{summary[:reviews]} review(s), " \
                      "#{summary[:devlog_reviews]} devlog review(s); " \
                      "#{summary[:synced]} synced, #{summary[:sync_skipped]} skipped (no integrity check)"
    summary
  end
end
