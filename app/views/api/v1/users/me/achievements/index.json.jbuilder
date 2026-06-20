json.achievements @achievements do |a|
  achievement = a[:achievement]
  earned = a[:earned]
  expose_slug = earned || achievement.visible?

  json.slug expose_slug ? achievement.slug : nil
  json.name achievement.display_name(earned: earned)
  json.description (earned || achievement.visible?) ? achievement.description : achievement.secret_hint
  json.icon achievement.icon
  json.earned earned
  json.earned_at a[:earned_at]
  json.progress achievement.show_progress?(earned: earned) ? a[:progress] : nil
  json.stardust_reward expose_slug ? achievement.stardust_reward : nil
end

json.stats do
  json.earned @stats[:earned]
  json.total @stats[:total]
end
