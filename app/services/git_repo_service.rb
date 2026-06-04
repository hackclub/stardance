require "base64"

class GitRepoService
  # Normalizes GitHub URLs by stripping /tree/, /blob/, /commit/, etc. to get the base repo URL
  def self.normalize_github_url(url)
    return url unless url.present?

    # Match GitHub URLs with paths like /tree/branch, /blob/branch/file, /commit/sha, etc.
    if url =~ %r{\Ahttps?://github\.com/([^/]+)/([^/]+?)(?:\.git)?(?:/(?:tree|blob|commit|pull|issues|releases|actions|wiki)(?:/|$).*)?(?:\.git)?\z}i
      "https://github.com/#{$1}/#{$2}.git"
    else
      url
    end
  end

  def self.is_cloneable?(repo_url, force: false)
    repo_url = normalize_github_url(repo_url)
    cache_key = "clone_check_#{Base64.encode64(repo_url)}"
    Rails.cache.delete(cache_key) if force
    Rails.cache.fetch(cache_key, expires_in: 1.minute) do
      _output, status = Open3.capture2e(
        {
          "GIT_TERMINAL_PROMPT" => "0",
          "GIT_ASKPASS" => "/bin/true",
          "GIT_CONFIG_GLOBAL" => "/dev/null",
          "GIT_CONFIG_SYSTEM" => "/dev/null"
        },
        "timeout", "2s",
        "git", "ls-remote", "--exit-code", "--heads",
        repo_url,
        chdir: "/"
      )
      status.success?
    end
  end
end
