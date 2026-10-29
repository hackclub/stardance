require "test_helper"

class TrackingLinkTest < ActiveSupport::TestCase
  test "nothing to link without a code" do
    assert_nil TrackingLink.for(nil)
    assert_nil TrackingLink.for("  ")
  end

  test "a pasted tracking url links to itself under a friendly label" do
    link = TrackingLink.for("https://www.dhl.com/track?id=ABC123")

    assert_equal "https://www.dhl.com/track?id=ABC123", link.url
    assert_equal TrackingLink::URL_LABEL, link.label
  end

  test "a non-web scheme is never treated as a url" do
    link = TrackingLink.for("javascript:alert(1)")

    assert_equal "https://parcelsapp.com/en/tracking/JAVASCRIPT%3AALERT%281%29", link.url
    assert_equal "javascript:alert(1)", link.label
  end

  test "hack club mail ids link to mail.hackclub.com" do
    assert_equal "https://mail.hackclub.com/pkg!abc123", TrackingLink.for("pkg!abc123").url
    assert_equal "https://mail.hackclub.com/ltr!xyz", TrackingLink.for("ltr!xyz").url
  end

  test "confidently recognised carrier numbers link to the carrier" do
    {
      "9400 1000 0000 0000 0000 00" => "https://tools.usps.com/go/TrackConfirmAction?tLabels=9400100000000000000000",
      "1z999aa10123456784" => "https://www.ups.com/track?tracknum=1Z999AA10123456784",
      "AB123456789GB" => "https://www.royalmail.com/track-your-item#/tracking-results/AB123456789GB",
      "H01ABC1234567890" => "https://www.evri.com/track/parcel/H01ABC1234567890/details"
    }.each do |code, url|
      assert_equal url, TrackingLink.for(code).url, "expected #{code} to link to its carrier"
    end
  end

  test "any other code links to the universal tracker" do
    {
      "01497129430383" => "https://parcelsapp.com/en/tracking/01497129430383", # DPD Germany
      "33G6W875695301000910909" => "https://parcelsapp.com/en/tracking/33G6W875695301000910909", # Australia Post domestic
      "CD123456789AU" => "https://parcelsapp.com/en/tracking/CD123456789AU", # Australia Post international
      "ord 12345" => "https://parcelsapp.com/en/tracking/ORD12345"
    }.each do |code, url|
      assert_equal url, TrackingLink.for(code).url, "expected #{code} to go to the universal tracker"
    end
  end

  test "a code that may not be a carrier code stays plain text unless recognised" do
    store_ref = TrackingLink.for("Bambu AU AU787303367675330561", universal: false)

    assert_nil store_ref.url
    assert_equal "Bambu AU AU787303367675330561", store_ref.to_slack_mrkdwn
    assert_equal "https://mail.hackclub.com/pkg!abc", TrackingLink.for("pkg!abc", universal: false).url
  end

  test "slack mrkdwn links the label and escapes it" do
    assert_equal "<https://mail.hackclub.com/pkg!abc|pkg!abc>", TrackingLink.for("pkg!abc").to_slack_mrkdwn
    assert_equal "A&amp;B &lt;1&gt;", TrackingLink.for("A&B <1>", universal: false).to_slack_mrkdwn
  end
end
