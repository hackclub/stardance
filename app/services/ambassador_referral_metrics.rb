class AmbassadorReferralMetrics
  POSTS = Post.arel_table
  POST_DEVLOGS = Post::Devlog.arel_table

  private_constant :POSTS, :POST_DEVLOGS

  def initialize(users)
    @user_ids = users.map(&:id).uniq
  end

  def logged_seconds
    @logged_seconds ||= compute_logged_seconds
  end

  def approved_seconds
    @approved_seconds ||= compute_approved_seconds
  end

  private
    def compute_logged_seconds
      return {} if @user_ids.empty?

      Post.of_devlogs(join: true)
          .where(user_id: @user_ids, post_devlogs: { deleted_at: nil })
          .group(:user_id)
          .sum(POST_DEVLOGS[:duration_seconds])
    end

    def compute_approved_seconds
      return {} if @user_ids.empty?

      approved_ships = Post.of_ship_events(join: true)
                           .where(user_id: @user_ids, post_ship_events: { certification_status: "approved" })
                           .pluck(POSTS[:user_id], POSTS[:project_id], POSTS[:created_at])
      return {} if approved_ships.empty?

      project_ids    = approved_ships.map { |ship| ship[1] }.uniq
      ship_times     = ship_times_by_project(project_ids)
      project_starts = Project.where(id: project_ids).pluck(:id, :created_at).to_h
      devlogs        = devlogs_by_project(project_ids)

      approved_ships.each_with_object(Hash.new(0)) do |(user_id, project_id, shipped_at), totals|
        window_start = ship_times[project_id].select { |time| time < shipped_at }.max || project_starts[project_id]
        totals[user_id] += devlogs[project_id].sum do |(logged_at, seconds)|
          logged_at.between?(window_start, shipped_at) ? seconds.to_i : 0
        end
      end
    end

    def ship_times_by_project(project_ids)
      Post.of_ship_events
          .where(project_id: project_ids)
          .order(:created_at)
          .pluck(:project_id, :created_at)
          .each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(project_id, time), grouped|
            grouped[project_id] << time
          end
    end

    def devlogs_by_project(project_ids)
      Post.of_devlogs(join: true)
          .where(project_id: project_ids, post_devlogs: { deleted_at: nil })
          .pluck(POSTS[:project_id], POSTS[:created_at], POST_DEVLOGS[:duration_seconds])
          .each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(project_id, logged_at, seconds), grouped|
            grouped[project_id] << [ logged_at, seconds ]
          end
    end
end
