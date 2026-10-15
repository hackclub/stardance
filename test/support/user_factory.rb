module UserFactory
  # `verified: true` clears the whole identity bar shipping and funding apply:
  # HCA-verified *and* eligible for YSWS prizes.
  def create_user(slack_id:, display_name:, hca_linked: true, verified: false)
    user = User.create!(
      slack_id: slack_id,
      display_name: display_name,
      email: "#{display_name}@example.test",
      verification_status: verified ? :verified : :needs_submission,
      ysws_eligible: verified
    )

    if hca_linked
      user.identities.create!(
        provider: "hack_club",
        uid: "hca-#{slack_id}",
        access_token: "fake-token-#{slack_id}"
      )
    end

    user
  end
end
