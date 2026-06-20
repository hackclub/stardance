class UserMailer < ApplicationMailer
  def onboarding_start(user)
    @user = user
    mail(to: user.email, from: "stardance@hackclub.com", reply_to: "team@stardance.hackclub.com")
  end

  def outpost(user)
    @user = user
    mail(to: user.email, from: "alexren@hackclub.com", reply_to: "outpost@hackclub.com")
  end
end
