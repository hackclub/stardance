require "test_helper"

class MissionIconTest < ActiveSupport::TestCase
  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze

  setup { @mission = create_mission }

  test "raster icons are served as a resized thumb" do
    @mission.icon.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "icon.png", content_type: "image/png")

    thumb = @mission.icon_thumb

    assert_kind_of ActiveStorage::VariantWithRecord, thumb
    assert_equal [ 128, 128 ], thumb.variation.transformations[:resize_to_limit]
  end

  test "svg icons are served as uploaded" do
    @mission.icon.attach(io: StringIO.new(%(<svg xmlns="http://www.w3.org/2000/svg"/>)), filename: "icon.svg", content_type: "image/svg+xml")

    assert_equal @mission.icon, @mission.icon_thumb
  end
end
