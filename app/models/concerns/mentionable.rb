module Mentionable
  extend ActiveSupport::Concern

  MENTION_PATTERN = /(?<=\A|[\s(])@([a-zA-Z0-9_-]+)/

  def mentioned_users
    return User.none unless body.present?

    usernames = body.scan(MENTION_PATTERN).flatten.map(&:downcase).uniq
    return User.none if usernames.empty?

    User.where("LOWER(display_name) IN (?)", usernames)
  end
end
