git_hash = ENV["SOURCE_COMMIT"] || `git rev-parse HEAD`.strip rescue "unknown"
commit_link = git_hash != "unknown" ? "https://github.com/hackclub/stardance/commit/#{git_hash}" : nil
short_hash = git_hash[0..7]
is_dirty = `git status --porcelain`.strip.length > 0 rescue false
version = is_dirty ? "#{short_hash}-dirty" : short_hash

Rails.application.config.server_start_time = Time.current
Rails.application.config.git_version = version
Rails.application.config.commit_link = commit_link
Rails.application.config.user_agent = "Stardance/#{version} (https://github.com/hackclub/stardance)"
