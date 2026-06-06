# frozen_string_literal: true

# Reachability probe used by Projects::ShipsController on re-ship to decide
# whether to auto-approve the ship. Delegates the actual HTTP work to
# Project#url_reachable? so the SafeUrl guard, GET request, redirect handling,
# and 5-minute cache are shared with the shipping_requirements check.
class ProjectUrlProbeService
  Result = Data.define(:ok, :failures) do
    def ok? = ok
  end

  def initialize(project)
    @project = project
  end

  def call
    failures = []
    failures << "demo URL didn't return success (#{@project.demo_url})" unless probe(@project.demo_url)
    failures << "repo URL didn't return success (#{@project.repo_url})" unless probe(@project.repo_url)
    Result.new(ok: failures.empty?, failures: failures)
  end

  private

  def probe(url)
    return false if url.blank?
    @project.url_reachable?(url)
  end
end
