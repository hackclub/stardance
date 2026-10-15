GIT_SHA_PATTERN = /\A[0-9a-f]{7,40}\z/i

git_hash = [ ENV["GIT_COMMIT_SHA"], ENV["SOURCE_COMMIT"] ].filter_map do |candidate|
  candidate = candidate.to_s.strip
  candidate if candidate.match?(GIT_SHA_PATTERN)
end.first

unless git_hash
  local_sha = `git rev-parse HEAD 2>/dev/null`.strip
  git_hash = local_sha if local_sha.match?(GIT_SHA_PATTERN)
end

git_hash ||= "unknown"

commit_link = git_hash != "unknown" ? "https://github.com/hackclub/stardance/commit/#{git_hash}" : nil
short_hash = git_hash[0..7]
is_dirty = `git status --porcelain 2>/dev/null`.strip.length > 0 rescue false
version = is_dirty ? "#{short_hash}-dirty" : short_hash

Rails.application.config.server_start_time = Time.current
Rails.application.config.git_version = version
Rails.application.config.commit_link = commit_link
Rails.application.config.user_agent = "Stardance/#{version} (https://github.com/hackclub/stardance)"
