module User::AmbassadorReferrals
  extend ActiveSupport::Concern

  class_methods do
    def ambassador_referral_seconds(users)
      user_ids = users.map(&:id).uniq

      {
        logged: ambassador_logged_seconds(user_ids),
        approved: ambassador_approved_seconds(user_ids)
      }
    end

    private
      def ambassador_logged_seconds(user_ids)
        return {} if user_ids.empty?

        Post.of_devlogs(join: true)
            .where(user_id: user_ids, post_devlogs: { deleted_at: nil })
            .group(:user_id)
            .sum(Post::Devlog.arel_table[:duration_seconds])
      end

      def ambassador_approved_seconds(user_ids)
        return {} if user_ids.empty?

        posts = Post.arel_table
        approved_ships = Post.of_ship_events(join: true)
                             .where(user_id: user_ids, post_ship_events: { certification_status: "approved" })
                             .pluck(posts[:user_id], posts[:project_id], posts[:created_at])
        return {} if approved_ships.empty?

        project_ids    = approved_ships.map { |ship| ship[1] }.uniq
        ship_times     = ambassador_ship_times_by_project(project_ids)
        project_starts = Project.where(id: project_ids).pluck(:id, :created_at).to_h
        devlogs        = ambassador_devlogs_by_project(project_ids)

        approved_ships.each_with_object(Hash.new(0)) do |(user_id, project_id, shipped_at), totals|
          window_start = ship_times[project_id].select { |time| time < shipped_at }.max || project_starts[project_id]
          totals[user_id] += devlogs[project_id].sum do |(logged_at, seconds)|
            logged_at.between?(window_start, shipped_at) ? seconds.to_i : 0
          end
        end
      end

      def ambassador_ship_times_by_project(project_ids)
        Post.of_ship_events
            .where(project_id: project_ids)
            .order(:created_at)
            .pluck(:project_id, :created_at)
            .each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(project_id, time), grouped|
              grouped[project_id] << time
            end
      end

      def ambassador_devlogs_by_project(project_ids)
        posts = Post.arel_table
        devlogs = Post::Devlog.arel_table

        Post.of_devlogs(join: true)
            .where(project_id: project_ids, post_devlogs: { deleted_at: nil })
            .pluck(posts[:project_id], posts[:created_at], devlogs[:duration_seconds])
            .each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(project_id, logged_at, seconds), grouped|
              grouped[project_id] << [ logged_at, seconds ]
            end
      end
  end
end
