module DevelopmentSeed
  class Likes
    include Helpers

    def self.call(users, posts)
      new(users, posts).call
    end

    def initialize(users, posts)
      @users = users
      @posts = posts
    end

    def call
      progress "Generating likes for #{@posts.count} posts"

      count = 0
      @posts.each do |post|
        next unless post.postable_type == "Post::Devlog"

        num_likes = random.rand(Config::MIN_LIKES_PER_POST..Config::MAX_LIKES_PER_POST)

        @users.sample(num_likes, random: random).each do |user|
          Like.create!(
            user: user,
            likeable: post.postable,
            created_at: post.created_at + random.rand(1..48).hours
          )
          count += 1
        end
      end

      done
      count
    end
  end
end
