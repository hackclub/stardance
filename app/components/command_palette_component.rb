class CommandPaletteComponent < ViewComponent::Base
  def initialize(current_user:, current_path: nil)
    @current_user = current_user
    @current_path = current_path
  end

  def initial_commands = Command.for_user(@current_user, current_path: @current_path)

  def search_url
    helpers.global_search_path
  end

  def mission_search_url
    helpers.search_missions_path
  end
end
