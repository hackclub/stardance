class Airtable::BaseSyncJob < ApplicationJob
  queue_as :literally_whenever
  notify_maintainers_on_exhaustion Norairrecord::Error, maintainers_slack_ids: [ "U05F4B48GBF" ], wait: :polynomially_longer, attempts: 3

  def self.perform_later(*args)
    return if SolidQueue::Job.where(class_name: name, finished_at: nil).exists?

    super
  end

  def perform
    synced_records = records_to_sync.to_a
    @synced_ids = synced_records.map(&:id)

    airtable_records = synced_records.map do |record|
      table.new(field_mapping(record))
    end

    # Deduplicate by primary key field to avoid Airtable "cannot update same record multiple times" error
    # Also filter out records with nil/blank primary keys
    airtable_records = airtable_records
      .reject { |r| r.fields[primary_key_field].blank? }
      .uniq { |r| r.fields[primary_key_field] }

    return if airtable_records.empty?

    begin
      table.batch_upsert(airtable_records, primary_key_field)
    rescue Norairrecord::Error => e
      raise unless e.message.include?("INVALID_VALUE_FOR_COLUMN") && e.message.include?("more than one record")

      Rails.logger.warn("[#{self.class.name}] Duplicate records in Airtable for #{primary_key_field}, syncing one at a time")
      airtable_records.each do |record|
        table.batch_upsert([ record ], primary_key_field)
      rescue Norairrecord::Error => individual_error
        Rails.logger.error("[#{self.class.name}] Failed to sync record #{record.fields[primary_key_field]}: #{individual_error.message}")
      end
    end
  ensure
    records.unscoped
           .where(id: @synced_ids)
           .update_all(synced_at_field => Time.now) if @synced_ids.present?
  end

  private

  def table_name
    raise NotImplementedError, "Subclass must implement #table_name"
  end

  def records
    raise NotImplementedError, "Subclass must implement #records"
  end

  def field_mapping(_record)
    raise NotImplementedError, "Subclass must implement #field_mapping"
  end

  def synced_at_field
    :synced_at
  end

  def primary_key_field
    "star_id"
  end

  def sync_limit
    10
  end

  def null_sync_limit
    sync_limit
  end

  def records_to_sync
    @records_to_sync ||= if null_sync_limit == sync_limit
      records.order("#{synced_at_field} ASC NULLS FIRST").limit(sync_limit)
    else
      null_count = records.where(synced_at_field => nil).count
      if null_count >= sync_limit
        records.where(synced_at_field => nil).limit(null_sync_limit)
      else
        remaining = sync_limit - null_count
        null_sql = records.unscope(:includes).where(synced_at_field => nil).to_sql
        non_null_sql = records.unscope(:includes).where.not(synced_at_field => nil).order("#{synced_at_field} ASC").limit(remaining).to_sql
        records.unscope(:includes).from("(#{null_sql} UNION ALL #{non_null_sql}) AS #{records.table_name}")
      end
    end
  end

  def table
    @table ||= Norairrecord.table(
      Rails.application.credentials&.airtable&.api_key || ENV["AIRTABLE_API_KEY"],
      Rails.application.credentials&.airtable&.base_id || ENV["AIRTABLE_BASE_ID"],
      table_name
    )
  end
end
