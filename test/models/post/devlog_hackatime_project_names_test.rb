require "test_helper"

class Post::DevlogHackatimeProjectNamesTest < ActiveSupport::TestCase
  test "a names snapshot keeps commas inside a project name" do
    devlog = Post::Devlog.new(hackatime_project_names_snapshot: [ "my,project" ])

    assert_equal [ "my,project" ], devlog.hackatime_project_names
  end

  test "a legacy csv snapshot resolves against the known project names" do
    devlog = Post::Devlog.new(hackatime_projects_key_snapshot: "my,project,api")

    assert_equal [ "my,project", "api" ], devlog.hackatime_project_names(known_names: [ "my,project", "api" ])
  end

  test "an ambiguous legacy csv snapshot stays unresolved" do
    devlog = Post::Devlog.new(hackatime_projects_key_snapshot: "a,b")

    assert_nil devlog.hackatime_project_names(known_names: [ "a,b", "a", "b" ])
  end

  test "legacy test and import snapshots have no hackatime names" do
    assert_equal [], Post::Devlog.new(hackatime_projects_key_snapshot: "test").hackatime_project_names
    assert_equal [], Post::Devlog.new(hackatime_projects_key_snapshot: "journal-import").hackatime_project_names
    assert_equal [ "solo" ], Post::Devlog.new(hackatime_projects_key_snapshot: "solo").hackatime_project_names
  end
end
