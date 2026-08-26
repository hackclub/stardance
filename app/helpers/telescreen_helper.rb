# frozen_string_literal: true

module TelescreenHelper
  DEFAULT_BASE = "https://telescreen.hackclub.com"
  JOE_HOSTS = %w[joe.fraud.hackclub.com].freeze

  def telescreen_base_url
    raw = Rails.application.config.telescreen_url.presence || DEFAULT_BASE
    raw.to_s.chomp("/")
  end

  def telescreen_subject_url(identifier)
    return if identifier.blank?

    id = numeric_id?(identifier) ? identifier.to_s : identifier.to_s.upcase
    "#{telescreen_base_url}/subjects/#{ERB::Util.url_encode(id)}"
  end

  def telescreen_hackatime_overview_url(hackatime_uid, project: nil)
    return if hackatime_uid.blank?

    query = { u: hackatime_uid }
    query[:p] = project if project.present?
    "#{telescreen_base_url}/workbench/hackatime/overview?#{query.to_query}"
  end

  def telescreen_hackatime_url(hackatime_uid: nil, slack_id: nil)
    return telescreen_hackatime_overview_url(hackatime_uid) if hackatime_uid.present?
    return if slack_id.blank?

    slack = slack_id.to_s.upcase
    "#{telescreen_base_url}/workbench/hackatime?slack=#{ERB::Util.url_encode(slack)}"
  end

  # Deep-links a single Lapse timelapse into Telescreen's lapse workbench, which
  # keys on the owner's Hackatime uid (u) and the lapse id (t).
  def telescreen_lapse_url(hackatime_uid:, lapse_id:)
    return if hackatime_uid.blank? || lapse_id.blank?

    "#{telescreen_base_url}/workbench/lapse?u=#{ERB::Util.url_encode(hackatime_uid.to_s)}&t=#{ERB::Util.url_encode(lapse_id.to_s)}"
  end

  def displayed_telescreen_url(url)
    uri = URI.parse(url.to_s)
    return url unless uri.is_a?(URI::HTTP) && uri.host.present?

    host = uri.host.delete_prefix("www.").downcase
    return uri.to_s unless JOE_HOSTS.include?(host)

    case uri.path
    when %r{\A/profile/([^/]+)/?\z}
      telescreen_subject_url(Regexp.last_match(1))
    when %r{\A/cases?/(\d+)/?\z}
      "#{telescreen_base_url}/joe/cases/#{Regexp.last_match(1)}"
    else
      uri.to_s
    end
  rescue URI::InvalidURIError
    url
  end

  private

  def numeric_id?(identifier)
    identifier.to_s.match?(/\A\d+\z/)
  end
end
