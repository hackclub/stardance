module GitHost
  class GitCli < Base
    def self.handles?(url)
      url.match?(%r{^(https?://|git@)}) && !Github.handles?(url)
    end

    def provider_name
      host = URI.parse(repo_url).host rescue nil
      host || "git"
    end

    def provider_display_name
      name = provider_name
      # Capitalize known platforms nicely
      case name
      when "gitlab.com"
        "GitLab"
      when "codeberg.org"
        "Codeberg"
      when "bitbucket.org"
        "Bitbucket"
      when /sr\.ht$/, /git\.sr\.ht$/
        "SourceHut"
      else
        name.capitalize
      end
    end

    def fetch_commits(since: nil, per_page: nil)
      return [] unless repo_url.present?

      Dir.mktmpdir("git_sync") do |tmpdir|
        clone_path = File.join(tmpdir, "repo")

        unless clone_repo(clone_path)
          Rails.logger.error("Failed to clone #{repo_url}")
          return []
        end

        parse_git_log(clone_path, since: since)
      end
    end

    protected

    def parse_url!
      @owner = nil
      @repo = nil
    end

    def normalize_commit(raw)
      raw
    end

    private

    def clone_repo(path)
      result = system(
        {
          "GIT_TERMINAL_PROMPT" => "0",
          "GIT_ASKPASS" => "/bin/true",
          "GIT_CONFIG_GLOBAL" => "/dev/null",
          "GIT_CONFIG_SYSTEM" => "/dev/null"
        },
        "git", "clone",
        "--bare",
        "--filter=blob:none",
        "--single-branch",
        "--no-tags",
        "--config", "core.hooksPath=/dev/null",
        "--config", "protocol.file.allow=never",
        "--config", "protocol.ext.allow=never",
        repo_url, path,
        out: File::NULL, err: File::NULL
      )
      result
    end

    def parse_git_log(clone_path, since: nil)
      format = "%H%n%s%n%b%n%an%n%ae%n%aI%n---COMMIT_END---"
      cmd = [ "git", "-C", clone_path, "log", "--format=#{format}" ]
      cmd += [ "--since=#{since.iso8601}" ] if since

      output, status = Open3.capture2(*cmd)
      return [] unless status.success?

      parse_log_output(output)
    end

    def parse_log_output(output)
      output.split("---COMMIT_END---").filter_map do |block|
        lines = block.strip.split("\n")
        next if lines.size < 5

        sha = lines[0]
        subject = lines[1]
        body_lines = lines[2..-4] || []
        author_name = lines[-3]
        author_email = lines[-2]
        authored_at = lines[-1]

        message = ([ subject ] + body_lines).join("\n").strip

        {
          sha: sha,
          message: message,
          author_name: author_name,
          author_email: author_email,
          authored_at: Time.parse(authored_at),
          url: build_commit_url(sha),
          additions: nil,
          deletions: nil,
          files_changed: nil
        }
      rescue ArgumentError
        nil
      end
    end

    def build_commit_url(sha)
      return nil unless repo_url.present?

      base = repo_url.sub(/\.git$/, "")

      if base.include?("gitlab")
        "#{base}/-/commit/#{sha}"
      elsif base.include?("bitbucket")
        "#{base}/commits/#{sha}"
      else
        "#{base}/commit/#{sha}"
      end
    end
  end
end
