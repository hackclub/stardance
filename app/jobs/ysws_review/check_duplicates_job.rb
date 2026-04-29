class YswsReview::CheckDuplicatesJob < ApplicationJob
  queue_as :default

  def perform
    records_to_check = source_table.all(
      max_records: 10,
      filter: "BLANK() = {Duplicate?}",
      sort: { "Created at": "asc" }
    )

    return if records_to_check.empty?

    puts "Found #{records_to_check.count} records to check for duplicates"

    records_to_update = []

    records_to_check.each do |record|
      code_url = record.fields["Code URL"]

      unless code_url.present?
        puts "Skipping record #{record.id} - no Code URL"
        next
      end

      duplicate_record = find_duplicate_in_unified_db(code_url)

      if duplicate_record
        puts "Found duplicate for #{code_url}: #{duplicate_record.id}"
        record["Duplicate?"] = duplicate_record.id
      else
        puts "No duplicate found for #{code_url}"
        record["Duplicate?"] = "N/A"
      end

      records_to_update << record
    end

    if records_to_update.any?
      source_table.batch_upsert(records_to_update, "id")
      puts "Successfully updated #{records_to_update.count} records with duplicate status"
    end
  end

  private

  def normalized_code_url_for_filter(code_url)
    normalized = code_url.to_s.strip
    normalized = normalized.sub(%r{\Ahttps?://}i, "")
    normalized = normalized.sub(%r{\.git\z}i, "")
    normalized = normalized.split("#").first
    # Escape single quotes for Airtable formula strings
    normalized.gsub("'", "''")
  end

  def find_duplicate_in_unified_db(code_url)
    normalized_code_url = normalized_code_url_for_filter(code_url)

    filter = "AND(" \
             "FIND('#{normalized_code_url}', " \
             "SUBSTITUTE(SUBSTITUTE(SUBSTITUTE({Code URL}, 'https://', ''), 'http://', ''), '.git', ''))," \
             " NOT({YSWS} = 'Stardance')" \
             ")"

    unified_db_table.all(
      filter: filter
    ).first
  end

  def source_table
    @source_table ||= Norairrecord.table(
      ENV["UNIFIED_DB_INTEGRATION_AIRTABLE_KEY"],
      "appNF8MGrk5KKcYZx",
      "ysws_submission"
    )
  end

  def unified_db_table
    @unified_db_table ||= Norairrecord.table(
      ENV["UNIFIED_DB_INTEGRATION_AIRTABLE_KEY"],
      "app3A5kJwYqxMLOgh",
      "Approved Projects"
    )
  end
end
