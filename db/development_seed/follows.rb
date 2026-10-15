module DevelopmentSeed
  class Follows
    include Helpers

    def self.call(users, projects)
      new(users, projects).call
    end

    def initialize(users, projects)
      @users = users
      @projects = projects
    end

    def call
      progress "Generating follows"

      user_follow_count = create_user_follows
      project_follow_count = create_project_follows

      done
      { user_follows: user_follow_count, project_follows: project_follow_count }
    end

    private

    def create_user_follows
      count = 0
      @users.each do |follower|
        # each user follows a percentage of other users
        num_to_follow = (@users.count * Config::FOLLOW_PERCENTAGE).to_i
        @users.reject { |u| u.id == follower.id }.sample(num_to_follow, random: random).each do |followed|
          Follow.create!(
            follower: follower,
            followed: followed,
            created_at: [ follower.created_at, followed.created_at ].max + random.rand(1..10).days
          )
          count += 1
        end
      end
      count
    end

    def create_project_follows
      count = 0
      @users.each do |user|
        # each user follows a percentage of projects they don't own
        other_projects = @projects.reject { |p| p.users.include?(user) }
        num_to_follow = (other_projects.count * Config::PROJECT_FOLLOW_PERCENTAGE).to_i

        other_projects.sample(num_to_follow, random: random).each do |project|
          ProjectFollow.create!(
            user: user,
            project: project,
            created_at: [ user.created_at, project.created_at ].max + random.rand(1..10).days
          )
          count += 1
        end
      end
      count
    end
  end
end
