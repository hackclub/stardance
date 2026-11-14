module Virality
  class ProjectReview
    SELF_HOSTED = %w[github.io vercel.app netlify.app pages.dev itch.io].freeze
    MANY_MENTIONS = 5
    STATES = {
      "pending" => "Open", "on_hold" => "On hold", "awaiting_confirmation" => "Awaiting confirmation",
      "scheduled" => "Scheduled", "approved" => "Approved", "rejected" => "Rejected"
    }.freeze

    Group = Struct.new(:url, :mentions, :warning, keyword_init: true) do
      def pending = mentions.select { |mention| mention.status == :pending }
      def first_submitted_at = mentions.map(&:created_at).min
    end

    attr_reader :project, :mentions

    def self.for(mentions, scheduled_ids:)
      mentions.group_by(&:project).map { |project, grouped| new(project, grouped, scheduled_ids: scheduled_ids) }
    end

    # The query stays because some sites identify posts by it (HN item?id=).
    def self.link_key(url)
      uri = URI.parse(url.to_s.strip)
      host = uri.host.to_s.downcase.delete_prefix("www.").delete_prefix("m.")
      video = youtube_id(uri, host)
      return "youtube:#{video}" if video

      query = URI.decode_www_form(uri.query.to_s).reject { |name, _| tracking_param?(name) }.sort
      key = "#{host}#{uri.path.to_s.chomp('/').downcase}"
      key += "?#{URI.encode_www_form(query)}" if query.any?
      key.presence || url.to_s.strip.downcase
    rescue URI::InvalidURIError, ArgumentError
      url.to_s.strip.downcase
    end

    TRACKING_PARAMS = %w[fbclid gclid igsh igshid ref s si t].freeze

    def self.tracking_param?(name)
      name.start_with?("utm_") || TRACKING_PARAMS.include?(name)
    end

    def self.youtube_id(uri, host)
      return uri.path.delete_prefix("/").split("/").first if host == "youtu.be"
      return unless host.end_with?("youtube.com")

      Rack::Utils.parse_query(uri.query.to_s)["v"].presence || uri.path[%r{\A/(?:shorts|live|embed)/([^/?]+)}, 1]
    end

    def self.warning_for(url, project)
      host = URI.parse(url.to_s.strip).host.to_s.downcase.delete_prefix("www.")
      return "Not a valid link" if host.blank?
      return "Localhost link, nobody else can open it" if host == "localhost" || host.match?(/\A[\d.]+\z/)
      return "Hack Club platform, doesn't count" if host == "hackclub.com" || host.end_with?(".hackclub.com")
      return "Links to the project itself, not a post about it" if own_site?(host, project)
      return "Not a listed platform" unless Virality::Evidence.platform_for(url)

      nil
    rescue URI::InvalidURIError
      "Not a valid link"
    end

    def self.own_site?(host, project)
      demo_host = URI.parse(project.demo_url.to_s).host.to_s.downcase.delete_prefix("www.")
      host == demo_host.presence || SELF_HOSTED.any? { |domain| host.end_with?(".#{domain}") }
    rescue URI::InvalidURIError
      false
    end

    def initialize(project, mentions, scheduled_ids:)
      @project = project
      @mentions = mentions.sort_by { |mention| [ mention.created_at, mention.id ] }
      @scheduled_ids = scheduled_ids
    end

    def groups
      @groups ||= mentions.group_by { |mention| self.class.link_key(mention.url) }.values.map do |grouped|
        Group.new(url: grouped.first.url, mentions: grouped, warning: self.class.warning_for(grouped.first.url, project))
      end.sort_by { |group| [ group.pending.any? ? 0 : 1, group.first_submitted_at ] }
    end

    def pending = mentions.select { |mention| mention.status == :pending }
    def editable?(mention) = mention.status == :pending && !@scheduled_ids.include?(mention.id)
    def oldest_pending_at = pending.map(&:created_at).min
    def newest_at = mentions.map(&:created_at).max

    def counts
      @counts ||= mentions.group_by { |mention| state_of(mention) }.transform_values(&:size)
    end

    def state_of(mention)
      return "scheduled" if @scheduled_ids.include?(mention.id)
      return mention.status.to_s unless mention.status == :pending
      return "awaiting_confirmation" if mention.proposed_action
      return "on_hold" if mention.on_hold_at?

      "pending"
    end

    def flags
      @flags ||= [].tap do |flags|
        repeats = groups.sum { |group| group.mentions.size - 1 }
        flags << [ :bad, "#{pluralize(repeats, 'repeat submission')} of the same link" ] if repeats.positive?
        flags << [ :bad, "Project is deleted" ] if project.deleted?
        flags << [ :bad, "Project hasn't passed review (#{project.ship_status.humanize.downcase})" ] if !project.deleted? && project.ship_status != "approved"
        warned = groups.count { |group| group.pending.any? && group.warning }
        flags << [ :bad, "#{pluralize(warned, 'open link')} unlikely to qualify" ] if warned.positive?
        silent = pending.count { |mention| mention.submitter_notes.blank? }
        flags << [ :bad, "#{pluralize(silent, 'open mention')} with no description" ] if silent.positive?
        flags << [ :bad, "#{mentions.size} mentions submitted" ] if mentions.size >= MANY_MENTIONS
        approved = counts["approved"].to_i
        flags << [ :good, "#{approved} already approved" ] if approved.positive?
      end
    end

    def red_flags = flags.count { |severity, _| severity == :bad }

    private

    def pluralize(count, noun) = ActionController::Base.helpers.pluralize(count, noun)
  end
end
