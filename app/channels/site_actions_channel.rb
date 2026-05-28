class SiteActionsChannel < ApplicationCable::Channel
  def subscribed
    stream_from "site_actions"
  end
end
