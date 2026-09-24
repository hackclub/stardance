# frozen_string_literal: true

# Updates the ban state of every Airtable submission Unified hasn't taken yet,
# for rows from before bans triggered resyncs
#
# Two kinds of people are behind a row that still reads clean:
#   - banned in Stardance before User#ban! resynced finished reviews. Their
#     reviews are resynced directly.
#   - banned on Hackatime (from Telescreen) but not yet in Stardance. Their
#     trust levels are read in batches from Hackatime's admin API, which works
#     even though a Hackatime ban blocks the user's own token, and the ban
#     resyncs their reviews itself.
#
# Rows Unified already has are skipped by YswsAirtableSyncJob and would have
# to be fixed manually
#
# Needs to run in a worker console, for the hackatime admin key to be set
#
# Usage:
#   OneTime::RefreshUnsubmittedHackatimeBansJob.perform_now                  # dry run
#   OneTime::RefreshUnsubmittedHackatimeBansJob.perform_now(dry_run: false)  # bans and resyncs
class OneTime::RefreshUnsubmittedHackatimeBansJob < ApplicationJob
  queue_as :literally_whenever

  LOG_PREFIX = "[RefreshUnsubmittedHackatimeBans]"
  BATCH_SIZE = 1000

  Result = Struct.new(:already_banned, :hackatime_banned, :no_hackatime, :unknown, :failed, keyword_init: true) do
    def summary = to_h.map { |group, user_ids| "#{group}=#{user_ids.size}" }.join(" ")
  end

  def perform(dry_run: true)
    @dry_run = dry_run
    @result = Result.new(already_banned: [], hackatime_banned: [], no_hackatime: [], unknown: [], failed: [])

    users = User.where(id: Certification::Ysws.rewritable_in_airtable.select(:user_id)).includes(:hackatime_identity)
    log "starting: #{users.count} users have a submission not yet in Unified"

    users.find_in_batches(batch_size: BATCH_SIZE).with_index(1) do |batch, number|
      process_batch(batch)
      log "batch #{number} done (#{batch.size} users), running totals: #{@result.summary}"
    end

    log "finished: #{@result.summary}"
    %i[already_banned hackatime_banned unknown failed].each do |group|
      log "#{group} user ids: #{@result[group].inspect}" if @result[group].any?
    end
    @result
  end

  private

  def process_batch(batch)
    banned, unbanned = batch.partition(&:banned?)
    banned.each { |user| act_on(user, :already_banned, "resync") { user.resync_ysws_reviews_to_airtable! } }

    linked, unlinked = unbanned.partition(&:hackatime_identity)
    @result.no_hackatime.concat(unlinked.map(&:id))
    return if linked.empty?

    by_uid = linked.index_by { |user| user.hackatime_identity.uid.to_s }
    trust_levels = HackatimeService.fetch_trust_levels(by_uid.keys)

    if trust_levels.nil?
      @result.unknown.concat(by_uid.values.map(&:id))
      log "trust level lookup failed, #{by_uid.size} users left unknown", level: :error
      return
    end

    by_uid.each do |uid, user|
      case trust_levels[uid]
      when "red"
        act_on(user, :hackatime_banned, "ban") { user.ban!(reason: User::HackatimeSync::HACKATIME_BAN_REASON) }
      when nil
        @result.unknown << user.id
        log "user=#{user.id} hackatime_uid=#{uid} not found on Hackatime", level: :warn
      end
    end
  end

  def act_on(user, group, action)
    @result[group] << user.id
    log "user=#{user.id} #{group}: #{@dry_run ? "would #{action}" : action}"
    yield unless @dry_run
  rescue StandardError => e
    @result.failed << user.id
    log "user=#{user.id} #{action} failed: #{e.class}: #{e.message}", level: :error
  end

  def log(message, level: :info)
    Rails.logger.public_send(level, "#{LOG_PREFIX}#{' DRY RUN' if @dry_run} #{message}")
  end
end
