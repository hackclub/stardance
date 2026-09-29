class BukuX3::RefreshJob < ApplicationJob
  queue_as :default

  limits_concurrency to: 1, key: "bukux3_refresh", duration: 5.minutes

  def perform
    BukuX3::Refresh.call
  end
end
