class User
  Role = Data.define(:id, :name, :description) do
    include ActiveModel::Conversion
    extend ActiveModel::Naming

    self::ALL = [
      new(0, :super_admin, "Can assign other users admin"),
      new(1, :admin, "Can do everything except assign or remove admin"),
      new(2, :fraud_dept, "Can issue negative payouts, cancel grants & shop orders, but not reject or ban users; access to Blazer; access to read-only admin User w/o PII"),
      new(3, :project_certifier, "Approve/reject if project work meets Shipwright standards"),
      new(4, :ysws_reviewer, "Can approve/reject projects for YSWS DB"),
      new(5, :fulfillment_person, "Can approve/reject/on-hold shop orders, fulfill them, and see addresses; access to read-only admin User w/ pII"),
      new(6, :helper, "Support team with read-only access to users (no PII), projects, and shop orders"),
      new(7, :flavortime, "Can access the Flavortime admin dashboard"),
      new(9, :shop_manager, "Can create/edit draft shop items and view orders without PII")
    ].freeze

    self::SLUGGED = self::ALL.index_by(&:name).freeze
    self::ALL_SLUGS = self::SLUGGED.keys.freeze

    class << self
      def all = self::ALL

      def slugged = self::SLUGGED

      def all_slugs = self::ALL_SLUGS

      def find(slug) = self::SLUGGED.fetch(slug.to_sym)

      alias_method :[], :find
    end

    def to_param = name

    def persisted? = true
  end
end
