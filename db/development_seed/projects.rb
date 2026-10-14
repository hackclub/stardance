module DevelopmentSeed
  class Projects
    include Helpers

    def self.call(users)
      new(users).call
    end

    def initialize(users)
      @users = users
    end

    def call
      progress "Generating projects for #{@users.count} users"

      projects = []
      @users.each do |user|
        Config::PROJECTS_PER_USER.times do |i|
          projects << create_project(user, i)
        end
      end

      # Add multi-user collaboration to ~20% of projects
      add_contributors(projects)

      done
      projects
    end

    private

    def create_project(owner, index)
      category = Project::AVAILABLE_CATEGORIES[random.rand(Project::AVAILABLE_CATEGORIES.size)]

      # generic names for projects
      adjective = %w[Super Mega Ultra Hyper Turbo Cyber Giga Nano Quantum Sonic Cosmic Solar Lunar].sample(random: random)
      noun = %w[App Bot Tool Script Engine Framework Library Portal Dashboard Tracker Manager].sample(random: random)
      title = "#{adjective} #{category} #{noun} #{index + 1}"

      project = Project.new(
        title: title,
        description: generate_description(category),
        project_categories: [ category ],
        # approved projects show up on the feed, drafts are private
        ship_status: random.rand < 0.7 ? "approved" : "draft",
        created_at: owner.created_at + random.rand(1..5).hours
      )

      project.save!

      project.memberships.create!(user: owner, role: :owner)

      project
    end

    def generate_description(category)
      [
        "A #{category.downcase} project focusing on clean architecture and performance.",
        "An experimental #{category.downcase} built to explore new technologies.",
        "A minimalist approach to #{category.downcase} with a focus on user experience.",
        "A community-driven #{category.downcase} project designed for modern workflows.",
        "Pushing the boundaries of #{category.downcase} with creative and efficient code."
      ].sample(random: random)
    end

    def add_contributors(projects)
      # 20% of projects get a contributor
      projects.sample(projects.size / 5, random: random).each do |project|
        owner = project.users.first
        contributor = @users.reject { |u| u.id == owner.id }.sample(random: random)

        # Project::Membership has a hard limit of 3 members
        if project.memberships.count < 3
          project.memberships.create(user: contributor, role: :contributor)
        end
      end
    end
  end
end
