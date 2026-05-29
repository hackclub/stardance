# frozen_string_literal: true

require "ipaddr"
require "resolv"

# Guards outbound HTTP requests to user-supplied URLs against SSRF.
#
# A url is safe to probe iff:
#   - it parses as a URI
#   - scheme is http or https
#   - host is present
#   - host resolves to at least one address, AND every resolved address is a
#     public/global IP (no loopback, private, link-local, multicast, etc.)
#
# Use before issuing a GET/HEAD to any user-supplied URL. Re-check the
# Location target on every redirect.
module SafeUrl
  ALLOWED_SCHEMES = %w[http https].freeze

  def self.safe_to_probe?(url)
    uri = URI.parse(url.to_s)
    return false unless ALLOWED_SCHEMES.include?(uri.scheme)
    return false if uri.host.blank?

    addresses = Resolv.getaddresses(uri.host)
    return false if addresses.empty?
    addresses.all? { |addr| public_ip?(addr) }
  rescue URI::InvalidURIError, Resolv::ResolvError, ArgumentError
    false
  end

  def self.public_ip?(ip_string)
    ip = IPAddr.new(ip_string)
    return false if ip.loopback? || ip.private? || ip.link_local?
    return false if ip.ipv4? && (ip.to_i == 0 || ip.to_i >= IPAddr.new("224.0.0.0").to_i)
    return false if ip.ipv6? && (ip == IPAddr.new("::") || ip.ipv4_mapped?)
    true
  rescue IPAddr::InvalidAddressError
    false
  end
end
