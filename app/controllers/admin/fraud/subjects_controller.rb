class Admin::Fraud::SubjectsController < Admin::ApplicationController
  SUBJECTS_PER_PAGE = 25

  def index
    authorize :fraud_subject, policy_class: Admin::FraudSubjectPolicy

    # The whole queue is ranked in one query and paginated in Ruby, the way the
    # shop fulfillment queue paginates its user groups: the ranking is a
    # GROUP BY, so a SQL page of it still needs a second query to count the
    # groups, and the queue is small enough (about a thousand people) that one
    # pass is cheaper than two round trips.
    subjects = Admin::Fraud::SubjectQueue.subjects
    @total_subjects = subjects.size
    @pagy, @subjects = pagy(:offset, subjects, limit: SUBJECTS_PER_PAGE)
    @users = User.where(id: @subjects.map(&:user_id)).index_by(&:id)
  end

  def show
    @user = User.find(params[:id])
    authorize :fraud_subject, policy_class: Admin::FraudSubjectPolicy

    @flags = Admin::Fraud::SubjectQueue.flags_for(@user)
    @orders = Admin::Fraud::SubjectQueue.orders_for(@user)
    @integrity_checks = Admin::Fraud::SubjectQueue.integrity_checks_for(@user)

    # Only Hackatime projects tied to a Stardance project can be deep-linked
    # into Telescreen's per-project view; the rest have no project to name.
    @hackatime_projects = @user.hackatime_projects.where.not(project_id: nil).includes(:project)
  end
end
