module Certification
  # Groups build recordings under the devlog whose time window they fall in, so a
  # reviewer sees each recording beside the devlog it contributed time to. Handles
  # both recording shapes: Lapse timelapses (recording time in :createdAt, epoch
  # milliseconds) and Lookout recordings (recording time in :recorded_at, a Time).
  #
  # A recording belongs to the half-open window [since, before) its recording time
  # lands in — the same rule YswsController buckets commits by, so a recording
  # lands under the devlog a commit at that instant would.
  class DevlogRecordingBucketer
    # recordings: LapseService and/or LookoutService hashes. Each exposes its
    #             recording time as :recorded_at (a Time) or :createdAt (epoch ms).
    # windows:    { post_devlog_id => { since: iso8601, before: iso8601 } }.
    # Returns:    { post_devlog_id => [recording, ...] }, only for devlogs with at
    #             least one recording; input order is preserved within a bucket.
    def self.call(recordings:, windows:)
      new(recordings, windows).call
    end

    def initialize(recordings, windows)
      @recordings = Array(recordings)
      @windows = windows.map do |devlog_id, w|
        [ devlog_id, Time.parse(w[:since]), Time.parse(w[:before]) ]
      end
    end

    def call
      @recordings.each_with_object({}) do |rec, buckets|
        devlog_id = devlog_id_for(rec)
        (buckets[devlog_id] ||= []) << rec if devlog_id
      end
    end

    private

    def devlog_id_for(recording)
      recorded_at = recorded_at_for(recording)
      return nil unless recorded_at

      match = @windows.find { |_id, since, before| recorded_at >= since && recorded_at < before }
      match&.first
    end

    # Lookout recordings already carry a Time in :recorded_at; Lapse timelapses
    # carry epoch milliseconds in :createdAt. Prefer the explicit Time.
    def recorded_at_for(recording)
      return recording[:recorded_at] if recording[:recorded_at].present?

      millis = recording[:createdAt]
      return nil if millis.blank?

      Time.zone.at(millis.to_i / 1000)
    end
  end
end
