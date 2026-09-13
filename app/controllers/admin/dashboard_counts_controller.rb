module Admin
  class DashboardCountsController < ApplicationController
    layout false

    COUNTS = {
      "shop_fulfillment" => -> {
        awaiting = ::ShopOrder.where(aasm_state: "awaiting_periodical_fulfillment")
        {
          count: awaiting.count,
          mine: awaiting.where(assigned_to_user_id: current_user.id).count
        }
      },
      "fraud_checks" => -> {
        ::ShopOrder.where(aasm_state: "pending").count +
          ::Project::Report.pending.where(reason: "fraud").count
      },
      # People waiting on a fraud verdict, not items: the per-person queue works
      # one person at a time, so its depth is the number of people in it.
      "fraud_subjects" => -> {
        ::Admin::Fraud::SubjectQueue.subjects.size
      },
      "ship_certifications" => -> {
        policy_scope(::Certification::Ship).where(status: "pending").count
      },
      "ysws_reviews" => -> {
        ::Certification::Ysws.pending.count
      },
      "mission_reviews" => -> {
        ::Mission::Submission.where(status: "pending", deleted_at: nil).count
      },
      "super_stars" => -> {
        ::Project.fire_nomination_pending.count
      }
    }.freeze

    def show
      authorize :admin, :index?
      count = COUNTS[params[:key]]
      return head :not_found unless count

      # A count is either a plain total or a hash carrying extras, e.g. how many
      # of the total belong to the viewer.
      result = instance_exec(&count)
      result = { count: result } unless result.is_a?(Hash)

      @key = params[:key]
      @count = result[:count]
      @mine = result[:mine]
    end
  end
end
