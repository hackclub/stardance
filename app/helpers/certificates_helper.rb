module CertificatesHelper
  def certificate_share_url(certificate)
    certificate_url(code: certificate.code)
  end

  def certificate_share_text(certificate)
    "I earned a Stardance certificate for logging " \
      "#{pluralize(certificate.hours_at_issue.floor, 'approved hour')} " \
      "building and shipping projects!"
  end

  def linkedin_share_url(url)
    "https://www.linkedin.com/sharing/share-offsite/?#{{ url: url }.to_query}"
  end

  # Deep link into LinkedIn's "add a license or certification" form, prefilled.
  def linkedin_add_to_profile_url(certificate)
    params = {
      startTask: "CERTIFICATION_NAME",
      name: "Stardance Certificate of Achievement",
      organizationId: 18031480, # linkedin.com/company/hack-club
      issueYear: certificate.created_at.year,
      issueMonth: certificate.created_at.month,
      certUrl: certificate_share_url(certificate),
      certId: certificate.code
    }
    "https://www.linkedin.com/profile/add?#{params.to_query}"
  end

  def x_share_url(url, text:)
    "https://x.com/intent/post?#{{ text: text, url: url }.to_query}"
  end
end
