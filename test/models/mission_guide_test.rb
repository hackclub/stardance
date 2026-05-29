require "test_helper"

class MissionGuideTest < ActiveSupport::TestCase
  # Builds a mission with one default variant. After the guide-unification
  # refactor (2026-05-26) the canonical content lives in
  # mission_guide_variants, not on Mission.guide_body. The factory mirrors
  # that — pass `guide_body:` to populate the default variant's body.
  def mission(guide_body: nil, language: "Default")
    m = Mission.create!(
      slug: "guide-test-#{SecureRandom.hex(4)}",
      name: "Guide test",
      description: "Description"
    )
    if guide_body.present?
      m.guide_variants.create!(language: language, body: guide_body, position: 0)
    end
    m
  end

  test "has_guide? false when no variants" do
    refute mission.has_guide?
  end

  test "has_guide? true when at least one variant exists" do
    assert mission(guide_body: "## Setup\n\nbody").has_guide?
  end

  test "guide_sections returns outline from h2 headings of the default variant" do
    m = mission(guide_body: "## Setup\n\nbody\n\n## Database schema\n\nmore body")
    sections = m.guide_sections
    assert_equal 2, sections.length
    assert_equal "Setup", sections[0][:text]
    assert_equal 0, sections[0][:index]
    assert_equal "Database schema", sections[1][:text]
    assert_equal 1, sections[1][:index]
  end

  test "guide_sections empty when no h2 headings" do
    m = mission(guide_body: "just a paragraph")
    assert_equal [], m.guide_sections
  end

  test "guide_sections returns one entry per shared step" do
    m = mission(guide_body: "## A\n\n## B\n\n## C")
    assert_equal 3, m.guide_sections.length
  end

  test "guide_body_updated_at stamps on the default variant when body changes" do
    m = mission(guide_body: "## Setup\n\nfirst write")
    first_stamp = m.guide_body_updated_at
    refute_nil first_stamp

    travel_to(2.minutes.from_now) do
      m.default_guide.update!(body: "## Setup\n\nsecond write")
      assert_in_delta Time.current, m.reload.guide_body_updated_at, 1.second
    end
  end

  test "available_languages reflects the variant tabs in position order" do
    m = mission(guide_body: "## A", language: "Ruby")
    m.guide_variants.create!(language: "Python", body: "## A", position: 1)
    assert_equal [ "Ruby", "Python" ], m.available_languages
  end
end
