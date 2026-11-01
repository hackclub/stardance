class ServerTimePolicy < ApplicationPolicy
  # Public clock/media metadata and the current viewer's playback availability.
  def show? = true
end
