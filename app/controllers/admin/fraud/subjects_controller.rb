class Admin::Fraud::SubjectsController < Admin::ApplicationController
  SUBJECTS_PER_PAGE = 25

  def index
    authorize :fraud_subject, policy_class: Admin::Fraud::SubjectPolicy

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
    authorize :fraud_subject, policy_class: Admin::Fraud::SubjectPolicy

    @flags = ::Project::Report.pending
      .where(project: @user.projects, reason: ::Project::Report::FRAUD_REVIEW_REASONS)
      .includes(:reporter, :project)
      .order(created_at: :asc)

    @orders = @user.shop_orders
      .where(aasm_state: ShopOrder::FRAUD_REVIEW_STATES)
      .includes(:shop_item)
      .order(created_at: :asc)

    @integrity_checks = ::Certification::Integrity.pending
      .joins(ship_event: :post)
      .where(posts: { user_id: @user.id })
      .includes(ship_event: { post: :project })
      .order(created_at: :asc)

    # Only Hackatime projects tied to a Stardance project can be deep-linked
    # into Telescreen's per-project view; the rest have no project to name.
    @hackatime_projects = @user.hackatime_projects.where.not(project_id: nil).includes(:project)
  end
end
