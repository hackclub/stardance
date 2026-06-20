# frozen_string_literal: true

class PostComponent < ViewComponent::Base
  attr_reader :post, :current_user, :theme, :compact, :show_likes, :show_comments, :show_reposts, :show_actions, :track_engagement

  def initialize(post:, current_user: nil, theme: :feed, compact: false, show_likes: true, show_comments: true, show_reposts: true, show_actions: true, track_engagement: true)
    @post = post
    @current_user = current_user
    @theme = theme
    @compact = compact
    @show_likes = show_likes
    @show_comments = show_comments
    @show_reposts = show_reposts
    @show_actions = show_actions
    @track_engagement = track_engagement
  end
end
