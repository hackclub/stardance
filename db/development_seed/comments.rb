module DevelopmentSeed
  class Comments
    include Helpers

    def self.call(users, posts)
      new(users, posts).call
    end

    def initialize(users, posts)
      @users = users
      @posts = posts
    end

    def call
      progress "Generating comments for #{@posts.count} posts"

      count = 0
      @posts.each do |post|
        next unless post.postable_type == "Post::Devlog"

        num_comments = random.rand(Config::MIN_COMMENTS_PER_POST..Config::MAX_COMMENTS_PER_POST)

        num_comments.times do
          create_comment(post)
          count += 1
        end
      end

      done
      count
    end

    private

    def create_comment(post)
      author = @users.sample(random: random)

      Comment.create!(
        user: author,
        commentable: post.postable,
        body: generate_comment_body,
        created_at: post.created_at + random.rand(1..24).hours
      )
    end

    def generate_comment_body
      [
        "This looks amazing! Great work.",
        "Really cool project, how did you handle the performance issues?",
        "Love the progress you're making here.",
        "The UI looks super clean. Nice job!",
        "Very interesting approach, I might try this in my own project.",
        "Keep it up! Can't wait to see the next update.",
        "Wow, that's a lot of progress for just one day.",
        "Is this open source? I'd love to contribute.",
        "Nice! Which library did you use for the rendering?",
        "This is so inspiring!"
      ].sample(random: random)
    end
  end
end
