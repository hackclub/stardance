require "test_helper"

class GitRepoServiceTest < ActiveSupport::TestCase
  test "normalize_github_url strips /tree/branch from GitHub URLs" do
    assert_equal "https://github.com/hackclub/stardance.git",
      GitRepoService.normalize_github_url("https://github.com/hackclub/stardance/tree/main")
  end

  test "normalize_github_url strips /tree/branch with nested paths" do
    assert_equal "https://github.com/hackclub/stardance.git",
      GitRepoService.normalize_github_url("https://github.com/hackclub/stardance/tree/main/src/app")
  end

  test "normalize_github_url strips /blob/branch/file from GitHub URLs" do
    assert_equal "https://github.com/hackclub/stardance.git",
      GitRepoService.normalize_github_url("https://github.com/hackclub/stardance/blob/main/README.md")
  end

  test "normalize_github_url strips /commit/sha from GitHub URLs" do
    assert_equal "https://github.com/hackclub/stardance.git",
      GitRepoService.normalize_github_url("https://github.com/hackclub/stardance/commit/abc123")
  end

  test "normalize_github_url strips /pull/ from GitHub URLs" do
    assert_equal "https://github.com/hackclub/stardance.git",
      GitRepoService.normalize_github_url("https://github.com/hackclub/stardance/pull/123")
  end

  test "normalize_github_url handles base repo URL without .git" do
    assert_equal "https://github.com/hackclub/stardance.git",
      GitRepoService.normalize_github_url("https://github.com/hackclub/stardance")
  end

  test "normalize_github_url preserves already normalized .git URLs" do
    assert_equal "https://github.com/hackclub/stardance.git",
      GitRepoService.normalize_github_url("https://github.com/hackclub/stardance.git")
  end

  test "normalize_github_url returns non-GitHub URLs unchanged" do
    assert_equal "https://gitlab.com/user/repo/tree/main",
      GitRepoService.normalize_github_url("https://gitlab.com/user/repo/tree/main")
  end

  test "normalize_github_url returns nil for nil input" do
    assert_nil GitRepoService.normalize_github_url(nil)
  end

  test "normalize_github_url returns empty string for empty input" do
    assert_equal "",
      GitRepoService.normalize_github_url("")
  end
end
