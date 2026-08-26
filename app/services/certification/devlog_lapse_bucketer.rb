module Certification
  # Groups Lapse timelapses under the devlog whose time window they fall in, so
  # a reviewer sees each recording beside the devlog it contributed time to.
  #
  # A lapse belongs to the half-open window [since, before) its recording time
  # (createdAt) lands in — the same rule YswsController buckets commits by, so a
  # lapse lands under the devlog a commit at that instant would.
  class DevlogLapseBucketer
    # timelapses: LapseService hashes, each with :createdAt (epoch milliseconds).
    # windows:    { post_devlog_id => { since: iso8601, before: iso8601 } }.
    # Returns:    { post_devlog_id => [timelapse, ...] }, only for devlogs with
    #             at least one lapse; input order is preserved within a bucket.
    def self.call(timelapses:, windows:)
      new(timelapses, windows).call
    end

    def initialize(timelapses, windows)
      @timelapses = Array(timelapses)
      @windows = windows.map do |devlog_id, w|
        [ devlog_id, Time.parse(w[:since]), Time.parse(w[:before]) ]
      end
    end

    def call
      @timelapses.each_with_object({}) do |tl, buckets|
        devlog_id = devlog_id_for(tl)
        (buckets[devlog_id] ||= []) << tl if devlog_id
      end
    end

    private

    def devlog_id_for(timelapse)
      recorded_at = recorded_at_for(timelapse)
      return nil unless recorded_at

      match = @windows.find { |_id, since, before| recorded_at >= since && recorded_at < before }
      match&.first
    end

    def recorded_at_for(timelapse)
      millis = timelapse[:createdAt]
      return nil if millis.blank?

      Time.zone.at(millis.to_i / 1000)
    end
  end
end
