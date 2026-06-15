class ExpeditionSyncJob < ApplicationJob
  queue_as :literally_whenever
  limits_concurrency to: 1, key: "expedition_sync", duration: 5.minutes

  def perform
    feed = AmbassadorService.expeditions
    return if feed.nil?

    rows = feed.map { |data| Expedition.attributes_from_api(data) }
    ids = rows.pluck(:airtable_id)

    Expedition.transaction do
      rows.each { |attrs| upsert(attrs) }
      Expedition.where.not(airtable_id: ids).delete_all
    end
  end

  private

  def upsert(attrs)
    record = Expedition.find_or_initialize_by(airtable_id: attrs[:airtable_id])
    record.assign_attributes(attrs.except(:airtable_id))
    record.save! if record.changed?
  end
end
