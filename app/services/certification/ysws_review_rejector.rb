# frozen_string_literal: true

module Certification
  # Auto-rejects a YSWS review that nobody can review by hand any more.
  #
  # Banning a user soft-deletes every project they own (User#ban! ->
  # #soft_delete_projects! -> Project#soft_delete!), which stamps deleted_at on
  # the project and on all of its devlogs. The review rows survive, so they sit
  # in the reviewer queue forever pointing at content that no longer renders.
  #
  # This mirrors what Admin::Certification::YswsController#complete does on a
  # manual completion — every devlog review lands on a decision, the review is
  # stamped reviewed_at/reviewer_id, and the Airtable sync is enqueued so the
  # unified YSWS base learns about the rejection. There is no status column on
  # certification_ysws_reviews: Certification::Ysws#review_status derives
  # :rejected on its own once reviewed_at is set and nothing is approved.
  class YswsReviewRejector
    # AVD — auto-rejections are attributed to them.
    REVIEWER_ID = 513

    WHODUNNIT = "Certification::YswsReviewRejector"

    # Devlog-level rejection justification per reason. Every rejected devlog
    # review needs a non-blank one (Certification::Devlog#reject! enforces it,
    # as does the manual complete action).
    JUSTIFICATIONS = {
      banned: "banned",
      project_deleted: "project deleted"
    }.freeze

    Result = Struct.new(:rejected, :devlog_reviews, :synced, keyword_init: true)

    class << self
      # The account auto-rejections are credited to, or nil when it is missing
      # (fresh database, test environment). A missing account never blocks the
      # rejection — an unattributed review beats a ban that raises halfway
      # through.
      def reviewer
        User.find_by(id: REVIEWER_ID)
      end

      # Clears every pending review belonging to `user`. The ban flow's entry
      # point, called once their projects are already soft-deleted.
      def reject_pending_for_user!(user)
        who = reviewer

        Certification::Ysws.pending.where(user_id: user.id).includes(:devlog_reviews).map do |review|
          new(review, reason: :banned, reviewer: who).call
        end
      end

      # Clears every pending review on `project`. The integrity flow's entry
      # point, called once a fraud verdict is committed on one of the project's
      # ship events.
      def reject_pending_for_project!(project)
        who = reviewer

        Certification::Ysws.pending.where(project_id: project.id).includes(:devlog_reviews).map do |review|
          new(review, reason: :banned, reviewer: who).call
        end
      end
    end

    attr_reader :review, :reason, :reviewer

    def initialize(review, reason:, reviewer: self.class.reviewer)
      raise ArgumentError, "unknown reason #{reason.inspect}" unless JUSTIFICATIONS.key?(reason)

      @review   = review
      @reason   = reason
      @reviewer = reviewer
    end

    def call
      return Result.new(rejected: false, devlog_reviews: 0, synced: false) unless review.pending?

      decided = 0

      PaperTrail.request(whodunnit: WHODUNNIT) do
        ActiveRecord::Base.transaction do
          review.devlog_reviews.reject(&:rejected?).each do |devlog_review|
            devlog_review.reject!(justification)
            decided += 1
          end

          # update! rather than the #complete action's update_columns, so the
          # audit trail carries the change. Dropping the claim keeps the review
          # out of the queue's unclaimed_or_claimed_by scope.
          review.update!(
            reviewer_id: reviewer&.id,
            reviewed_at: Time.current,
            claimed_by_id: nil,
            claimed_at: nil
          )
        end
      end

      Rails.logger.info "[YswsReviewRejector] review=#{review.id} reason=#{reason} " \
                        "devlog_reviews=#{decided} reviewer=#{reviewer&.id || 'none'}"

      Result.new(rejected: true, devlog_reviews: decided, synced: enqueue_sync)
    end

    private

    def justification
      JUSTIFICATIONS.fetch(reason)
    end

    # YswsAirtableSyncJob waits for the ship's integrity verdict, so a review
    # with no check yet is left for that verdict to sync.
    def enqueue_sync
      unless Certification::Integrity.exists?(ship_event_id: review.post_ship_event_id)
        Rails.logger.warn "[YswsReviewRejector] review=#{review.id} skipping Airtable sync — " \
                          "no integrity check for ship event ##{review.post_ship_event_id}"
        return false
      end

      Certification::YswsAirtableSyncJob.perform_later(review.id)
      true
    end
  end
end
