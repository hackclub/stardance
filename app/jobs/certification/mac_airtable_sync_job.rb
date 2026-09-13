module Certification
  class MACAirtableSyncJob < ApplicationJob
    queue_as :literally_whenever

    retry_on Norairrecord::Error, wait: :exponentially_longer, attempts: 3 do |job, error|
      Rails.logger.error "[MacAirtableSyncJob] Exhausted retries: #{error.message}"
    end
    retry_on Faraday::Error, wait: :exponentially_longer, attempts: 3 do |job, error|
      Rails.logger.error "[MacAirtableSyncJob] Exhausted retries: #{error.message}"
    end

    SYNC_LIMIT = 500

    def self.perform_later(*args)
      return if SolidQueue::Job.where(class_name: name, finished_at: nil).exists?

      super
    end

    def perform
      analyses = analyses_needing_sync
      return if analyses.empty?

      review_id_map = build_review_id_map

      synced_ids = []
      skipped = 0

      records_to_update = analyses.filter_map do |analysis|
        rid = analysis.ysws_review_id.to_s
        record = review_id_map[rid]

        unless record
          Rails.logger.debug { "[MacAirtableSyncJob] No airtable record for review ##{rid}, skipping" }
          skipped += 1
          next
        end

        record["mac_ai_pct"] = extract_ai_pct(analysis)
        record["mac_flags"] = extract_flags(analysis)
        synced_ids << analysis.id
        record
      end

      if records_to_update.any?
        table.batch_update(records_to_update)
      end

      if synced_ids.any?
        Certification::MACAnalysis.where(id: synced_ids).update_all("airtable_synced_at = updated_at")
      end

      Rails.logger.info "[MacAirtableSyncJob] Synced #{synced_ids.size}, skipped #{skipped} (no airtable record)"
    end

    private

      def analyses_needing_sync
        with_airtable_review = Certification::MACAnalysis
          .joins(:ysws_review)
          .where.not(certification_ysws_reviews: { airtable_synced_at: nil })

        never_synced = with_airtable_review.where(certification_mac_analyses: { airtable_synced_at: nil })
        stale = with_airtable_review.where("certification_mac_analyses.airtable_synced_at < certification_mac_analyses.updated_at")

        ids = never_synced
          .or(stale)
          .select("DISTINCT ON (certification_mac_analyses.ysws_review_id) certification_mac_analyses.id")
          .order(:ysws_review_id, generated_at: :desc)

        Certification::MACAnalysis
          .where(id: ids)
          .order(:updated_at)
          .limit(SYNC_LIMIT)
          .to_a
      end

      def build_review_id_map
        map = {}
        table.all(fields: [ "review_id" ]).each do |record|
          rid = record["review_id"]
          map[rid] = record if rid.present?
        end
        map
      end

      def extract_ai_pct(analysis)
        report = analysis.report
        return nil unless report.is_a?(Hash)

        pct = report.dig("signals", "ai_coding_pct")
        pct&.round(1)
      end

      def extract_flags(analysis)
        report = analysis.report
        return "" unless report.is_a?(Hash)

        Array.wrap(report["flags"])
          .grep(Hash)
          .filter_map { |f| f["type"].presence }
          .uniq
          .sort
          .join(",")
      end

      def table
        @table ||= Certification::YswsAirtable.table
      end
  end
end
