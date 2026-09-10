module Admin
  module Fraud
    # Ranks the people with fraud work waiting on them, so a reviewer works one
    # person at a time instead of three separate queues that keep handing them
    # the same person.
    #
    # Three sources feed it: flags (Project::Report on a reason the fraud team
    # owns), shop orders awaiting a verdict, and pending integrity checks. Each
    # item scores its age in days times a weight, and a person's priority is
    # their single highest-scoring item. Highest wins.
    #
    # MAX rather than SUM: one genuinely old flag should outrank a pile of fresh
    # integrity checks, and nobody should reach the top of the queue on volume
    # alone.
    class SubjectQueue
      FLAG_WEIGHT = 3.0
      ORDER_WEIGHT = 2.0
      INTEGRITY_WEIGHT = 1.0

      Subject = Data.define(:user_id, :priority, :flag_count, :order_count, :integrity_count, :oldest_at) do
        def item_count = flag_count + order_count + integrity_count
      end

      # One row per person with work waiting, ordered by priority. Banned people
      # are left out: a ban already rejects their orders and soft-deletes their
      # projects, so there is no verdict left to give.
      def self.relation
        ::User.where(banned: false)
              .joins("INNER JOIN (#{items_sql}) fraud_items ON fraud_items.user_id = users.id")
              .group("users.id")
              .select(<<~SQL.squish)
                users.id AS user_id,
                MAX(fraud_items.weight * EXTRACT(EPOCH FROM (NOW() - fraud_items.created_at)) / 86400.0) AS priority,
                COUNT(*) FILTER (WHERE fraud_items.kind = 'flag') AS flag_count,
                COUNT(*) FILTER (WHERE fraud_items.kind = 'order') AS order_count,
                COUNT(*) FILTER (WHERE fraud_items.kind = 'integrity') AS integrity_count,
                MIN(fraud_items.created_at) AS oldest_at
              SQL
              .order(Arel.sql("priority DESC"))
      end

      def self.subjects(relation = self.relation)
        relation.map do |row|
          Subject.new(
            user_id: row.user_id,
            priority: row.priority.to_f,
            flag_count: row.flag_count,
            order_count: row.order_count,
            integrity_count: row.integrity_count,
            oldest_at: row.oldest_at
          )
        end
      end

      # A flag lands on every member of the project it was filed against: on a
      # team project there is no way to tell from the report which member the
      # claim is about, so all of them get looked at.
      def self.flags
        ::Project::Report.pending
          .where(reason: ::Project::Report::FRAUD_REVIEW_REASONS)
          .joins("INNER JOIN project_memberships ON project_memberships.project_id = project_reports.project_id")
          .select("project_memberships.user_id AS user_id, project_reports.created_at AS created_at")
      end

      def self.orders
        ::ShopOrder.where(aasm_state: ::ShopOrder::FRAUD_REVIEW_STATES)
                   .select("shop_orders.user_id AS user_id, shop_orders.created_at AS created_at")
      end

      def self.integrity_checks
        ::Certification::Integrity.pending
          .joins("INNER JOIN posts ON posts.postable_id = certification_integrities.ship_event_id AND posts.postable_type = 'Post::ShipEvent'")
          .select("posts.user_id AS user_id, certification_integrities.created_at AS created_at")
      end

      # The same three sources, narrowed to one person. The subject page and the
      # verdict responses both read them from here so a filter can never drift
      # between the queue and the page it opens.
      def self.flags_for(user)
        ::Project::Report.pending
          .where(project: user.projects, reason: ::Project::Report::FRAUD_REVIEW_REASONS)
          .includes(:reporter, :project)
          .order(created_at: :asc)
      end

      def self.orders_for(user)
        user.shop_orders
            .where(aasm_state: ::ShopOrder::FRAUD_REVIEW_STATES)
            .includes(:shop_item)
            .order(created_at: :asc)
      end

      # The checks a cascading verdict settled alongside the one actually
      # decided: same person, same project, no longer pending. Their rows leave
      # the list on its own refresh, but nothing else knows they moved.
      def self.cascaded_siblings_of(check, user:)
        project_id = check.ship_event&.post&.project_id
        return ::Certification::Integrity.none if project_id.nil?

        ::Certification::Integrity.where.not(status: :pending)
          .where.not(id: check.id)
          .joins(ship_event: :post)
          .where(posts: { user_id: user.id, project_id: project_id })
      end

      # The next person a reviewer should pick up: highest priority first,
      # skipping the one they just finished and anyone another reviewer is
      # currently holding.
      def self.next_subject_id(reviewer:, after: nil)
        held = ::FraudSubjectClaim.active.where.not(reviewer_id: reviewer.id).pluck(:subject_id)
        excluded = ([ after&.id ] + held).compact

        scope = relation
        scope = scope.where.not(id: excluded) if excluded.any?
        scope.first&.user_id
      end

      def self.integrity_checks_for(user)
        ::Certification::Integrity.pending
          .joins(ship_event: :post)
          .where(posts: { user_id: user.id })
          .includes(ship_event: { post: :project })
          .order(created_at: :asc)
      end

      def self.items_sql
        [
          branch_sql(flags, "flag", FLAG_WEIGHT),
          branch_sql(orders, "order", ORDER_WEIGHT),
          branch_sql(integrity_checks, "integrity", INTEGRITY_WEIGHT)
        ].join(" UNION ALL ")
      end

      def self.branch_sql(scope, kind, weight)
        "SELECT user_id, created_at, #{::ActiveRecord::Base.connection.quote(kind)} AS kind, #{weight} AS weight FROM (#{scope.to_sql}) AS #{kind}_items"
      end

      private_class_method :items_sql, :branch_sql
    end
  end
end
