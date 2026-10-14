class UserMailer < ApplicationMailer
  def onboarding_start(user)
    @user = user
    mail(to: user.email, from: "stardance@hackclub.com", reply_to: "team@stardance.hackclub.com")
  end
end
