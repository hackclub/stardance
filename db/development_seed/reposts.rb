module DevelopmentSeed
  class Reposts
    include Helpers

    def self.call(users, posts)
      new(users, posts).call
    end

    def initialize(users, posts)
      @users = users
      @posts = posts
    end

    def call
      devlog_posts = @posts.select { |p| p.postable_type == "Post::Devlog" }

      progress "Generating reposts for #{devlog_posts.count} devlogs"

      count = 0
      devlog_posts.each do |original_post|
        num_reposts = random.rand(Config::MIN_REPOSTS_PER_POST..Config::MAX_REPOSTS_PER_POST)

        potential_reposters = @users.reject { |u| u.id == original_post.user_id }

        potential_reposters.sample(num_reposts, random: random).each do |reposter|
          if create_repost(original_post, reposter)
            count += 1
          end
        end
      end

      done
      count
    end

    private

    def create_repost(original_post, reposter)
      repost = Post::Repost.new(
        user: reposter,
        original_post: original_post,
        body: [ nil, "This is cool!", "Check this out!", "Love this project.", "Great progress here!" ].sample(random: random),
        created_at: original_post.created_at + random.rand(1..24).hours
      )

      return false unless repost.save

      Post.create!(
        user: reposter,
        project: nil,
        postable: repost,
        created_at: repost.created_at
      )

      true
    rescue ActiveRecord::RecordInvalid
      false
    end
  end
end
