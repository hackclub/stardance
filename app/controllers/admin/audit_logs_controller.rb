require "csv"

module Admin
  class AuditLogsController < Admin::ApplicationController
    def index
      authorize :admin, :access_audit_logs?

      @versions = PaperTrail::Version.order(created_at: :desc)

      # Hide system activities by default (where whodunnit is nil)
      @show_system = params[:show_system] == "1"
      unless @show_system
        @versions = @versions.where.not(whodunnit: nil)
      end

      # Apply filters
      if params[:item_type].present?
        @versions = @versions.where(item_type: params[:item_type])
      end

      if params[:item_id].present?
        @versions = @versions.where(item_id: params[:item_id])
      end

      if params[:event].present?
        @versions = @versions.where(event: params[:event])
      end

      if params[:whodunnit].present?
        @versions = @versions.where(whodunnit: params[:whodunnit])
      end

      if params[:start_date].present?
        @versions = @versions.where("created_at >= ?", params[:start_date])
      end

      if params[:end_date].present?
        @versions = @versions.where("created_at <= ?", params[:end_date])
      end

      # Text search in object_changes
      if params[:search].present?
        @versions = @versions.where("object_changes::text ILIKE ?", "%#{params[:search]}%")
      end

      # CSV export (before pagination)
      respond_to do |format|
        format.html
      end

      # Pagination
      @pagy, @versions = pagy(:offset, @versions, limit: 50)

      # Get unique item types and users for filters
      @item_types = PaperTrail::Version.distinct.pluck(:item_type).compact.sort
      @events = PaperTrail::Version.distinct.pluck(:event).compact.sort
      @users = User.where(id: PaperTrail::Version.distinct.pluck(:whodunnit).compact).order(:display_name)

      # For item_id filter, show the affected record info
      @affected_record = find_affected_record if params[:item_id].present? && params[:item_type].present?
    end

    def show
      authorize :admin, :access_audit_logs?
      @version = PaperTrail::Version.find(params[:id])
    end

    private

    # Map of allowed item types to their classes for safe lookup
    ALLOWED_ITEM_CLASSES = {
      "User" => "User",
      "User::Identity" => "User::Identity",
      "Project" => "Project",
      "Project::Membership" => "Project::Membership",
      "Project::Report" => "Project::Report",
      "ShopOrder" => "ShopOrder",
      "ShopItem" => "ShopItem",
      "Post" => "Post",
      "Post::Devlog" => "Post::Devlog",
      "Post::ShipEvent" => "Post::ShipEvent",
      "Post::FireEvent" => "Post::FireEvent",
      "Comment" => "Comment",
      "LedgerEntry" => "LedgerEntry",
      "Vote" => "Vote",
      "Like" => "Like",
      "Rsvp" => "Rsvp",
      "FunnelEvent" => "FunnelEvent",
      "FulfillmentPayoutRun" => "FulfillmentPayoutRun"
    }.freeze

    def generate_csv(versions)
      users_by_id = User.where(id: versions.pluck(:whodunnit).compact.uniq).index_by { |u| u.id.to_s }
      CSV.generate(headers: true) do |csv|
        csv << [ "ID", "Timestamp", "User", "Event", "Model", "Record ID", "Changes" ]
        versions.each do |v|
          user = users_by_id[v.whodunnit.to_s]
          csv << [
            v.id,
            v.created_at.iso8601,
            user&.display_name || v.whodunnit || "System",
            v.event,
            v.item_type,
            v.item_id,
            v.object_changes.to_json
          ]
        end
      end
    end

    def find_affected_record
      return nil unless params[:item_type].present? && params[:item_id].present?
      return nil unless ALLOWED_ITEM_CLASSES.key?(params[:item_type])

      class_name = ALLOWED_ITEM_CLASSES[params[:item_type]]
      klass = class_name.constantize
      klass.find_by(id: params[:item_id])
    rescue StandardError
      nil
    end
  end
end
