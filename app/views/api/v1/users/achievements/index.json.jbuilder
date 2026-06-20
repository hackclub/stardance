json.achievements @achievements do |a|
  achievement = a[:achievement]

  json.slug achievement.slug
  json.name achievement.name
  json.description achievement.description
  json.icon achievement.icon
  json.earned_at a[:earned_at]
end
