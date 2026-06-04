require "test_helper"

# SSRF guard tests. The PR that introduced DNS-rebinding protection shipped
# without specs, so these lock in the security-critical behavior: which hosts
# pass verification. DNS is injected (addresses:) so the logic is exercised
# without real network resolution.
class SafeUrlTest < ActiveSupport::TestCase
  # --- public_ip? classification -------------------------------------------

  test "public_ip? rejects loopback, private, and link-local ranges" do
    %w[127.0.0.1 10.0.0.5 192.168.1.1 172.16.0.1 169.254.169.254 ::1].each do |ip|
      assert_not SafeUrl.public_ip?(ip), "#{ip} must not be treated as public"
    end
  end

  test "public_ip? accepts ordinary public addresses" do
    %w[1.1.1.1 8.8.8.8 93.184.216.34].each do |ip|
      assert SafeUrl.public_ip?(ip), "#{ip} should be public"
    end
  end

  test "public_ip? rejects IPv4-mapped IPv6 that smuggles a private address" do
    assert_not SafeUrl.public_ip?("::ffff:127.0.0.1")
  end

  # --- resolve_and_verify! --------------------------------------------------

  test "resolve_and_verify! rejects non-http schemes" do
    error = assert_raises(SafeUrl::Error) { SafeUrl.resolve_and_verify!("ftp://example.com") }
    assert_match(/scheme/i, error.message)
  end

  test "resolve_and_verify! rejects a blank host" do
    assert_raises(SafeUrl::Error) { SafeUrl.resolve_and_verify!("http:///path") }
  end

  test "resolve_and_verify! rejects a host that resolves only to a private IP" do
    assert_raises(SafeUrl::Error) do
      SafeUrl.resolve_and_verify!("http://intranet.example", addresses: [ "10.0.0.1" ])
    end
  end

  test "resolve_and_verify! rejects an unresolvable host" do
    assert_raises(SafeUrl::Error) do
      SafeUrl.resolve_and_verify!("http://nope.invalid", addresses: [])
    end
  end

  test "resolve_and_verify! returns the verified public IP" do
    assert_equal "93.184.216.34",
                 SafeUrl.resolve_and_verify!("http://example.com", addresses: [ "93.184.216.34" ])
  end

  # The regression the hardening targets: a host with BOTH a public and a
  # private record must NOT be probed, because a second resolution could land
  # on the private one. The PR's find-first-public would accept it; strict
  # all?-public rejects it before any request goes out.
  test "a host resolving to mixed public and private IPs is rejected" do
    mixed = [ "93.184.216.34", "127.0.0.1" ]
    assert_not SafeUrl.safe_to_probe?("http://rebind.example", addresses: mixed),
               "a host that also resolves to a private IP must be rejected"
    assert_raises(SafeUrl::Error) do
      SafeUrl.resolve_and_verify!("http://rebind.example", addresses: mixed)
    end
  end

  test "safe_to_probe? is true for an all-public host" do
    assert SafeUrl.safe_to_probe?("https://example.com", addresses: [ "93.184.216.34" ])
  end
end
