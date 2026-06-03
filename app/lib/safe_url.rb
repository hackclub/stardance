# frozen_string_literal: true

require "ipaddr"
require "resolv"
require "net/http"

# Guards outbound HTTP requests to user-supplied URLs against SSRF.
#
# Two steps approach that eliminates DNS rebinding (TOCTOU):
#  step - 1
#   - resolves the hostname, reject any private/linklocal/loopback IP
#  step - 2
#   - return verified ip so callers can pin the connection to it,
#   preventing a second DNS lookup from resolving to a different address
module SafeUrl
  ALLOWED_SCHEMES = %w[http https].freeze
  class Error < StandardError; end
  # `addresses` is injectable so tests can exercise the verification logic
  # without real DNS; in production it defaults to a live resolve.
  def self.resolve_and_verify!(url, addresses: nil)
    uri = URI.parse(url.to_s)
    raise Error, "Scheme not allowed" unless ALLOWED_SCHEMES.include?(uri.scheme)
    raise Error, "Host is blank"     if uri.host.blank?
    addresses ||= resolve_addresses(uri.host)
    raise Error, "Could not resolve host" if addresses.empty?

    # Require EVERY resolved address to be public, not just one. A host that
    # answers with both a public and a private record (a rebinding/split-horizon
    # trick) is treated as hostile and rejected outright. We still return a
    # single verified IP so callers can pin the socket to it.
    raise Error, "Host resolves to a non-public IP" unless addresses.all? { |addr| public_ip?(addr) }
    addresses.first
  rescue URI::InvalidURIError, Resolv::ResolvError, ArgumentError => e
    raise Error, e.message
  end
  def self.safe_to_probe?(url, addresses: nil)
    resolve_and_verify!(url, addresses: addresses)
    true
  rescue Error
    false
  end
  def self.safe_head(url, **opts)
    safe_request(:head, url, **opts)
  end

  def self.safe_get(url, **opts)
    safe_request(:get, url, **opts)
  end

  # Issue a pinned request to a user-supplied URL and follow redirects safely.
  # Every hop is re-resolved and re-verified, then the socket is pinned to the
  # verified IP via Net::HTTP#ipaddr= — so the address we checked is the address
  # we connect to, closing the DNS-rebinding (TOCTOU) window. The hostname still
  # drives SNI and TLS certificate verification, so HTTPS stays validated.
  def self.safe_request(method, url, headers: {}, limit: 3, open_timeout: 10, read_timeout: 10)
    raise Error, "Too many redirects" if limit <= 0

    uri         = URI.parse(url.to_s)
    verified_ip = resolve_and_verify!(url)

    http = Net::HTTP.new(uri.host, uri.port)
    http.ipaddr       = verified_ip
    http.use_ssl      = (uri.scheme == "https")
    http.open_timeout = open_timeout
    http.read_timeout = read_timeout

    request_class = (method == :head ? Net::HTTP::Head : Net::HTTP::Get)
    request = request_class.new(uri.request_uri)
    headers.each { |k, v| request[k] = v }

    response = http.request(request)
    return response unless response.is_a?(Net::HTTPRedirection) && response["location"]

    # Resolve relative Location headers against the current URL before the next
    # hop, otherwise a "/path" redirect would parse with a blank host.
    next_url = URI.join(uri.to_s, response["location"]).to_s
    safe_request(method, next_url, headers: headers, limit: limit - 1,
                 open_timeout: open_timeout, read_timeout: read_timeout)
  end
  # Single DNS chokepoint for live resolution. Tests bypass it by passing
  # `addresses:` into resolve_and_verify! instead.
  def self.resolve_addresses(host)
    Resolv.getaddresses(host)
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
