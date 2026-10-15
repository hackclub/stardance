module DevelopmentSeed
  class Devlogs
    include Helpers

    def self.call(projects)
      new(projects).call
    end

    def initialize(projects)
      @projects = projects
    end

    def call
      progress "Generating devlogs for #{@projects.count} projects"

      all_posts = []
      @projects.each do |project|
        num_devlogs = random.rand(Config::MIN_DEVLOGS_PER_PROJECT..Config::MAX_DEVLOGS_PER_PROJECT)

        num_devlogs.times do |i|
          all_posts << create_devlog(project, i)
        end
      end

      done
      all_posts
    end

    private

    def create_devlog(project, index)
      # pick a random member of the project to be the author
      author = project.users.sample(random: random)

      devlog = Post::Devlog.new(
        body: generate_body,
        # minimum 15 minutes required by validation
        duration_seconds: random.rand(15..120).minutes.to_i,
        created_at: project.created_at + (index + 1).days + random.rand(1..12).hours
      )

      image_path = Rails.root.join("app/assets/images/landing/how-this-works/card-left-bg.png")
      if File.exist?(image_path)
        devlog.attachments.attach(
          io: File.open(image_path),
          filename: "card-left-bg.jpg",
          content_type: "image/jpeg"
        )
      end

      devlog.save!

      post = Post.create!(
        user: author,
        project: project,
        postable: devlog,
        created_at: devlog.created_at
      )

      post
    end

    def generate_body
      intros = [
        "Today I worked on", "Just finished", "Making progress on",
        "Updates for", "Spent some time on", "Excited to share"
      ]
      tasks = [
        "the user interface components.", "the backend API integration.",
        "fixing some nasty bugs in the engine.", "refactoring the core logic.",
        "adding support for custom themes.", "improving the database performance.",
        "implementing the authentication flow.", "writing some unit tests.",
        "optimizing the rendering pipeline.", "polishing the user experience."
      ]
      outros = [
        "Feeling good about the progress!", "Still a lot to do, but getting there.",
        "Can't wait to ship this!", "The code is looking much cleaner now.",
        "Feedback is always welcome!", "More updates coming soon."
      ]

      "#{intros.sample(random: random)} #{tasks.sample(random: random)} #{outros.sample(random: random)}"
    end
  end
end
