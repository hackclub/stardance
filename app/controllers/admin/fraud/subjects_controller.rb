class Admin::Fraud::SubjectsController < Admin::ApplicationController
  SUBJECTS_PER_PAGE = 25

  def index
    authorize :fraud_subject, policy_class: Admin::FraudSubjectPolicy

    # The whole queue is ranked in one query and paginated in Ruby, the way the
    # shop fulfillment queue paginates its user groups: the ranking is a
    # GROUP BY, so a SQL page of it still needs a second query to count the
    # groups, and the queue is small enough (about a thousand people) that one
    # pass is cheaper than two round trips.
    subjects = Admin::Fraud::SubjectQueue.subjects_for(current_user)
    @total_subjects = subjects.size
    @pagy, @subjects = pagy(:offset, subjects, limit: SUBJECTS_PER_PAGE)
    @users = User.where(id: @subjects.map(&:user_id)).index_by(&:id)
  end

  def show
    @user = User.find(params[:id])
    authorize :fraud_subject, policy_class: Admin::FraudSubjectPolicy

    # Opening a person takes them for an hour, so two reviewers do not work
    # the same queue. A claim nobody refreshes simply lapses.
    claim = FraudSubjectClaim.claim(@user, current_user)
    @blocking_claim = FraudSubjectClaim.active.find_by(subject_id: @user.id) unless claim&.reviewer_id == current_user.id

    @flags = Admin::Fraud::SubjectQueue.flags_for(@user)
    @orders = Admin::Fraud::SubjectQueue.orders_for(@user)
    @integrity_checks = Admin::Fraud::SubjectQueue.integrity_checks_for(@user)

    approved_scope = @user.shop_orders.where(aasm_state: %w[awaiting_periodical_fulfillment fulfilled])
    @approved_orders_count = approved_scope.count
    @approved_orders = approved_scope.includes(:shop_item).order(created_at: :desc).limit(10)

    # Only Hackatime projects tied to a Stardance project can be deep-linked
    # into Telescreen's per-project view; the rest have no project to name.
    @hackatime_projects = @user.hackatime_projects.where.not(project_id: nil).includes(:project)
    @project_summaries = project_summaries_for(@user)
    @review_items = @flags.to_a + @orders.to_a + @integrity_checks.to_a
    @open_payout = FraudReviewPayout.unpaid.find_by(reviewer: current_user, subject: @user, completed_at: nil)
    @next_subject_id = Admin::Fraud::SubjectQueue.next_subject_id(reviewer: current_user, after: @user) if @review_items.empty?
  end

  private

  def project_summaries_for(user)
    ship_posts = Post.of_ship_events.where(user_id: user.id).includes(:ship_event).order(created_at: :desc).to_a
    project_ids = ship_posts.map(&:project_id).compact.uniq
    projects = Project.with_deleted.where(id: project_ids).index_by(&:id)
    devlogs_by_project = Post.of_devlogs(join: true)
                              .where(user_id: user.id, project_id: project_ids, post_devlogs: { deleted_at: nil })
                              .includes(:devlog)
                              .group_by(&:project_id)

    ship_posts.group_by(&:project_id).filter_map do |project_id, submissions|
      project = projects[project_id]
      next unless project

      key_seconds = Hash.new(0)
      devlogs_by_project.fetch(project_id, []).each do |post|
        keys = post.devlog.hackatime_projects_key_snapshot.to_s.split(",").map(&:strip).reject(&:blank?).sort
        label = keys.any? ? keys.join(" + ") : "No key snapshot"
        key_seconds[label] += post.devlog.duration_seconds.to_i
      end

      {
        project:,
        submissions: submissions.map(&:ship_event),
        payout: submissions.sum { |post| post.ship_event.payout.to_f },
        key_seconds: key_seconds.sort_by { |_, seconds| -seconds },
        total_seconds: key_seconds.values.sum
      }
    end
  end
end
