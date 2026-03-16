require_relative "test_helper"
require "open3"

class DownloaderTest < Minitest::Test
  URL = "https://www.youtube.com/watch?v=E9T78bT26sk&list=RDE9T78bT26sk&start_radio=1"

  def test_class_download_delegates_to_instance
    dummy_result = { path: "/tmp/file.mp3" }

    downloader_double = Minitest::Mock.new
    downloader_double.expect(:download, dummy_result, [URL])

    YtMediaEngine::Downloader.stub :new, ->(**_opts) { downloader_double } do
      result = YtMediaEngine::Downloader.download(URL, format: :audio)
      assert_equal dummy_result, result
    end

    downloader_double.verify
  end

  def test_download_raises_error_when_url_blank
    downloader = YtMediaEngine::Downloader.new

    assert_raises(YtMediaEngine::Error) do
      downloader.download("  ")
    end
  end

  def test_download_raises_error_for_unknown_format
    downloader = YtMediaEngine::Downloader.new(format: :unknown)

    error = assert_raises(YtMediaEngine::Error) do
      downloader.download(URL)
    end

    assert_match(/Unknown format/, error.message)
  end

  def test_successful_audio_download_returns_expected_structure
    stdout_json = {
      "title" => "Test video",
      "thumbnails" => [
        { "url" => "https://example.com/small.jpg", "width" => 120, "height" => 90 },
        { "url" => "https://example.com/big.jpg", "width" => 1920, "height" => 1080 }
      ]
    }.to_json

    status_success = Struct.new(:success?, :exitstatus).new(true, 0)

    downloader = YtMediaEngine::Downloader.new(
      format: :audio,
      audio_format: "mp3",
      quality: "bestaudio/best",
      output_dir: "tmp/test_yt_media_engine",
      yt_dlp_path: "custom-yt-dlp",
      ffmpeg_path: "custom-ffmpeg"
    )

    downloader.stub :pick_downloaded_file, "/abs/path/to/file.mp3" do
      downloader.stub :find_thumbnail_file, "/abs/path/to/thumb.jpg" do
        Open3.stub :capture3, [stdout_json, "", status_success] do
          result = downloader.download(URL)

          assert_equal "/abs/path/to/file.mp3", result[:path]
          assert_equal "Test video", result[:title]
          assert_equal "https://example.com/big.jpg", result[:thumbnail_url]
          assert_equal "/abs/path/to/thumb.jpg", result[:thumbnail_path]
          assert_kind_of Hash, result[:raw_metadata]
          assert_equal "Test video", result[:raw_metadata]["title"]
        end
      end
    end
  end

  def test_yt_dlp_failure_raises_error
    status_fail = Struct.new(:success?, :exitstatus).new(false, 1)
    downloader = YtMediaEngine::Downloader.new

    Open3.stub :capture3, ["", "some error from yt-dlp", status_fail] do
      error = assert_raises(YtMediaEngine::Error) do
        downloader.download(URL)
      end

      assert_match(/yt-dlp failed \(status=1\): some error from yt-dlp/, error.message)
    end
  end

  def test_invalid_metadata_json_raises_error
    status_success = Struct.new(:success?, :exitstatus).new(true, 0)
    downloader = YtMediaEngine::Downloader.new

    stdout = "{invalid json}\n"

    downloader.stub :pick_downloaded_file, "/abs/path/to/file.mp3" do
      Open3.stub :capture3, [stdout, "", status_success] do
        error = assert_raises(YtMediaEngine::Error) do
          downloader.download(URL)
        end

        assert_match(/Failed to parse yt-dlp metadata JSON/, error.message)
      end
    end
  end
end

