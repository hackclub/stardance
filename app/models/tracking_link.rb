# A shipment tracking code and where to follow it. Admins paste whatever the
# carrier gave them — a bare number, a full tracking URL, or a Hack Club mail
# id — and this is the one place that decides where it links, so the admin
# order page, the user's order list and Slack DMs all agree.
#
# Only formats we can identify with confidence get a carrier's own page; any
# other code goes to a multi-carrier tracker that detects the carrier itself,
# since many number formats (DPD, Australia Post, ...) are shared or ambiguous
# between carriers and countries.
class TrackingLink < Data.define(:code, :universal)
  HACK_CLUB_MAIL_PREFIXES = %w[pkg! ltr!].freeze

  # Matched against the code with spaces removed and upcased, since carriers
  # print long numbers in spaced groups ("9400 1000 ...").
  CARRIER_URLS = {
    /\A9[2-5]\d{18,24}\z/ => "https://tools.usps.com/go/TrackConfirmAction?tLabels=%s", # USPS
    /\A1Z[0-9A-Z]{16}\z/ => "https://www.ups.com/track?tracknum=%s", # UPS
    /\A[A-Z]{2}\d{9}GB\z/ => "https://www.royalmail.com/track-your-item#/tracking-results/%s", # Royal Mail
    /\AH[0-9A-Z]{15}\z/ => "https://www.evri.com/track/parcel/%s/details" # Evri
  }.freeze

  # Parcels (parcelsapp.com) reads the number from the path and auto-detects
  # the carrier.
  UNIVERSAL_TRACKER_URL = "https://parcelsapp.com/en/tracking/%s".freeze

  URL_LABEL = "Track your package".freeze

  # `universal: false` is for references that may not be carrier codes at all
  # (e.g. a store order number in external_ref): those only link when they're
  # recognisably trackable.
  def self.for(code, universal: true)
    new(code: code.to_s.strip, universal: universal) if code.present?
  end

  def url
    return code if web_url?
    return "https://mail.hackclub.com/#{code}" if code.start_with?(*HACK_CLUB_MAIL_PREFIXES)

    normalized = code.delete(" ").upcase
    CARRIER_URLS.each { |pattern, template| return format(template, normalized) if pattern.match?(normalized) }
    format(UNIVERSAL_TRACKER_URL, ERB::Util.url_encode(normalized)) if universal
  end

  # A pasted URL is long and meaningless to read, so it gets a friendly label;
  # anything else is shown as the code itself.
  def label
    web_url? ? URL_LABEL : code
  end

  def to_slack_mrkdwn
    text = label.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
    url ? "<#{url}|#{text}>" : text
  end

  private

  def web_url?
    uri = URI.parse(code)
    uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end
end
