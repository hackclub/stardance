require "test_helper"
require "tempfile"

class StardanceFinaleMediaTest < ActiveSupport::TestCase
  test "missing video disables playback without starting ffprobe" do
    Open3.stub(:capture3, ->(*) { flunk "must not probe a missing file" }) do
      assert_empty StardanceFinaleMedia.load(Rails.root.join("tmp/missing-finale.mp4"))
    end
  end

  test "reads the entire file duration and versions its public URL" do
    with_video do |path|
      Open3.stub(:capture3, [ "123.456\n", "", success ]) do
        media = StardanceFinaleMedia.load(path)
        assert_equal 123.456, media[:duration]
        assert_equal "/videos/finale.mp4?v=#{path.mtime.to_i}-#{path.size}", media[:url]
      end
    end
  end

  test "invalid metadata or failed probes disable playback" do
    with_video do |path|
      [ "N/A", "0", "-1", "NaN", "Infinity" ].each do |output|
        Open3.stub(:capture3, [ output, "", success ]) do
          assert_empty StardanceFinaleMedia.load(path)
        end
      end
      Open3.stub(:capture3, [ "10", "failure", Struct.new(:success?).new(false) ]) do
        assert_empty StardanceFinaleMedia.load(path)
      end
    end
  end

  test "missing ffprobe does not prevent the application from booting" do
    with_video do |path|
      Open3.stub(:capture3, ->(*) { raise Errno::ENOENT }) do
        assert_empty StardanceFinaleMedia.load(path)
      end
    end
  end

  private
    def success = Struct.new(:success?).new(true)

    def with_video
      Tempfile.create([ "finale", ".mp4" ]) { |file| yield Pathname.new(file.path) }
    end
end
