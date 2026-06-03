module User::StateFlags
  extend ActiveSupport::Concern

  DISMISSIBLE_THINGS = %w[home_intro flagship_ad shop_suggestion_box willsbuilds_banner shop_picks_intro slack_doodle].freeze

  def has_dismissed?(thing_name) = things_dismissed.include?(thing_name.to_s)

  def dismiss_thing!(thing_name)
    thing_name_str = thing_name.to_s
    raise ArgumentError, "Invalid thing to dismiss: #{thing_name_str}" unless DISMISSIBLE_THINGS.include?(thing_name_str)

    append_array_value_once(:things_dismissed, thing_name_str)
  end

  def undismiss_thing!(thing_name)
    thing_name_str = thing_name.to_s
    raise ArgumentError, "Invalid thing to dismiss: #{thing_name_str}" unless DISMISSIBLE_THINGS.include?(thing_name_str)

    remove_array_value(:things_dismissed, thing_name_str)
  end

  def onboarded? = onboarded_at.present?
  def hca_linked? = hack_club_identity.present?
  def guest? = !hca_linked?

  # True for guests who already started the first-project setup flow and own
  # a project that is gated behind finishing HCA link. Used to swap the
  # "Create your first project" banner copy and to redirect away from the
  # project show page.
  def has_pending_setup_project? = guest? && projects.exists?

  private
    def append_array_value_once(column, value)
      values = things_dismissed || []
      return if values.include?(value)

      col = self.class.connection.quote_column_name(column)
      updated = self.class.where(id: id)
        .where.not("#{col} @> ARRAY[?]::varchar[]", value)
        .update_all([ "#{col} = array_append(#{col}, ?), updated_at = NOW()", value ])
      return false if updated.zero?

      self.things_dismissed = values + [ value ]
      true
    end

    def remove_array_value(column, value)
      values = things_dismissed || []
      return unless values.include?(value)

      col = self.class.connection.quote_column_name(column)
      self.class.where(id: id)
        .update_all([ "#{col} = array_remove(#{col}, ?), updated_at = NOW()", value ])
      self.things_dismissed = values - [ value ]
      true
    end
end
