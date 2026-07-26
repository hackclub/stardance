module Admin
  class ApplicationController < ::ApplicationController
    include Pundit::Authorization

    layout "admin"

    before_action :prevent_admin_access_while_impersonating
    before_action :set_paper_trail_whodunnit
    after_action :verify_authorized

    def index
      authorize :admin
      if current_user.helper? && !current_user.admin?
        redirect_to admin_support_path
      elsif current_user.fraud_dept? && !current_user.admin?
        redirect_to admin_fraud_path
      elsif current_user.shop_manager? && !current_user.admin?
        redirect_to admin_shop_path
      elsif current_user.has_role?(:raffle_admin) && !current_user.admin?
        redirect_to admin_raffles_path
      elsif current_user.workshop_manager? && !current_user.admin?
        redirect_to admin_workshops_path
      else
        @admin_dashboard_sections = admin_dashboard_sections
        @admin_dashboard_tools = admin_dashboard_tools
        @weighted_grants_count = weighted_grants_count if show_weighted_grants?
      end
    end

    private

    def admin_dashboard_sections
      [
        {
          title: "People and trust",
          accent: "mint",
          description: "Account safety and moderation hubs.",
          links: [
            dashboard_link(
              label: "Users",
              description: "Search profiles, roles, and account state.",
              path: admin_users_path
            ),
            dashboard_link(
              label: "Fraud dashboard",
              description: "Investigate suspicious activity and review queues.",
              path: admin_fraud_path
            ),
            dashboard_link(
              label: "Support dashboard",
              description: "Handle helper workflows and quick user fixes.",
              path: admin_support_path
            )
          ]
        },
        {
          title: "Programs and reviews",
          accent: "lilac",
          description: "Program operations and review queues.",
          links: [
            dashboard_link(
              label: "Missions",
              description: "Manage mission content and ownership.",
              path: admin_missions_path
            ),
            dashboard_link(
              label: "Mission reviews",
              description: "Review incoming mission submissions.",
              path: admin_mission_reviews_path
            ),
            dashboard_link(
              label: "Workshops",
              description: "Create and edit workshop schedules.",
              path: admin_workshops_path
            ),
            dashboard_link(
              label: "Raffles",
              description: "Run referral raffles and anti-abuse tooling.",
              path: admin_raffles_path
            )
          ]
        },
        {
          title: "Commerce and payouts",
          accent: "yellow",
          description: "Shop operations and payout oversight.",
          links: [
            dashboard_link(
              label: "Shop dashboard",
              description: "Manage products, stock, and storefront settings.",
              path: admin_shop_path
            ),
            dashboard_link(
              label: "Payout reviews",
              description: "Approve payout submissions from reviewers.",
              path: admin_payout_reviews_path
            ),
            dashboard_link(
              label: "Ledger",
              description: "Inspect global stardust balance changes.",
              path: admin_ledger_entries_path
            )
          ]
        },
        {
          title: "Comms and campaigns",
          accent: "blue",
          description: "Announcements, templates, and campaign utilities.",
          links: [
            dashboard_link(
              label: "Messages",
              description: "Send admin broadcasts to cohorts.",
              path: admin_messages_path
            ),
            dashboard_link(
              label: "Email templates",
              description: "Create and manage reusable email drafts.",
              path: admin_email_templates_path
            ),
            dashboard_link(
              label: "Super stars",
              description: "Review and manage fire nominations.",
              path: admin_super_stars_path
            ),
            dashboard_link(
              label: "Projects",
              description: "Browse and moderate project records.",
              path: admin_projects_path
            )
          ]
        }
      ]
    end

    def admin_dashboard_tools
      [
        dashboard_link(
          label: "Program funnel",
          description: "Top-level traffic and conversion insights.",
          path: admin_funnel_path
        ),
        dashboard_link(
          label: "SQL explorer",
          description: "Run internal dashboards and ad-hoc queries.",
          path: admin_blazer_path
        ),
        dashboard_link(
          label: "Flipper",
          description: "Toggle runtime gates and rollout controls.",
          path: "/admin/flipper"
        ),
        dashboard_link(
          label: "Job queue",
          description: "Inspect failed jobs, retries, and workers.",
          path: admin_mission_control_jobs_path
        )
      ]
    end

    def dashboard_link(label:, description:, path:)
      {
        label:,
        description:,
        path:
      }
    end

    def show_weighted_grants?
      Flipper.enabled?(:show_wgs, current_user)
    end

    def weighted_grants_count
      approved_ship_hours = Post.of_ship_events(join: true)
        .where(post_ship_events: { certification_status: "approved" })
        .where(project_id: ::Project.select(:id))
        .sum("post_ship_events.hours_at_ship")

      (approved_ship_hours.to_f / 10.0).round(2)
    end

    def pundit_namespace(record)
      return record if record.is_a?(Array) && record.first == :admin

      [ :admin, record ]
    end

    def user_for_paper_trail
      impersonating? ? real_user&.id : current_user&.id
    end

    def prevent_admin_access_while_impersonating
      if impersonating?
        flash[:alert] = "You cannot access admin panels while impersonating. Stop impersonation first."
        redirect_to root_path
      end
    end
  end
end
