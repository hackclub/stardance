# frozen_string_literal: true

module Gorse::Ids
  def self.user(user) = "user:#{user.id}"

  def self.post(post) = "post:#{post.id}"

  def self.project(project) = "project:#{project.id}"

  def self.post_id(value)
    value.to_s.delete_prefix("post:").presence
  end

  def self.project_id(value)
    value.to_s.delete_prefix("project:").presence
  end
end
