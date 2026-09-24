# frozen_string_literal: true

# Updates the ban state of every Airtable submission, for rows from before
# bans triggered resyncs
#
# Two kinds of people are behind a row that still reads clean:
#   - banned in Stardance before User#ban! resynced finished reviews. Their
#     reviews are resynced directly.
#   - banned on Hackatime (from Telescreen) but not yet in Stardance, because
#     the ban only lands on a stats fetch. A forced fetch bans them here, and
#     the ban resyncs their reviews itself.
#
# Rows Unified already has are skipped by YswsAirtableSyncJob and would have
# to be fixed manually
#
# Usage:
#   OneTime::RefreshUnsubmittedHackatimeBansJob.perform_now                  # dry run
#   OneTime::RefreshUnsubmittedHackatimeBansJob.perform_now(dry_run: false)  # bans and resyncs
class OneTime::RefreshUnsubmittedHackatimeBansJob < ApplicationJob
  queue_as :literally_whenever

  LOG_PREFIX = "[RefreshUnsubmittedHackatimeBans]"

  Result = Struct.new(:already_banned, :hackatime_banned, :failed, keyword_init: true)

  def perform(dry_run: true)
    result = Result.new(already_banned: [], hackatime_banned: [], failed: [])
    user_ids = Certification::Ysws.rewritable_in_airtable.distinct.pluck(:user_id)

    User.where(id: user_ids).find_each do |user|
      if user.banned?
        result.already_banned << user.id
        user.resync_ysws_reviews_to_airtable! unless dry_run
      elsif hackatime_banned?(user, dry_run: dry_run)
        result.hackatime_banned << user.id
      end
    rescue StandardError => e
      result.failed << user.id
      Rails.logger.error "#{LOG_PREFIX} user=#{user.id} #{e.class}: #{e.message}"
    end

    Rails.logger.info "#{LOG_PREFIX}#{' DRY RUN' if dry_run} checked=#{user_ids.size} " \
                      "already_banned=#{result.already_banned.inspect} " \
                      "hackatime_banned=#{result.hackatime_banned.inspect} failed=#{result.failed.inspect}"
    result
  end

  private

  # A dry run reads the Hackatime verdict without acting on it. The real run
  # goes through the normal fetch, which bans the user when Hackatime says so.
  def hackatime_banned?(user, dry_run:)
    identity = user.hackatime_identity
    return false unless identity

    if dry_run
      HackatimeService.fetch_stats(identity.uid, access_token: identity.access_token)&.dig(:banned) || false
    else
      user.try_sync_hackatime_data!(force: true)
      user.banned?
    end
  end
end
