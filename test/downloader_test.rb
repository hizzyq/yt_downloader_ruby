# test/downloader_test.rb

require "minitest/autorun"
require "fileutils"
require_relative "../lib/yt_media_engine"

Thread.report_on_exception = false
class DownloaderTest < Minitest::Test
  URL = "https://www.youtube.com/watch?v=E9T78bT26sk"

  def setup
    @original_new    = YtMediaEngine::Downloader.method(:new)
    @new_was_stubbed = false
    @temp_files      = []
  end

  def teardown
    cleanup_temp_files
    if @new_was_stubbed
      YtMediaEngine::Downloader.define_singleton_method(:new, @original_new)
    end
  end

  # .download делегирует вызов экземпляру

  def test_class_download_delegates_to_instance
    @new_was_stubbed = true

    mock_downloader = Object.new
    def mock_downloader.download(_url)
      { path: "/tmp/file.mp3" }
    end

    YtMediaEngine::Downloader.define_singleton_method(:new) { |**_opts| mock_downloader }

    result = YtMediaEngine::Downloader.download(URL, format: :audio)

    assert_equal "/tmp/file.mp3", result[:path],
                 "Метод .download должен возвращать результат экземпляра"
  end

  # ---------------------------------------------------------------------------
  # #download — валидация URL
  # ---------------------------------------------------------------------------

  def test_download_raises_error_when_url_blank
    downloader = YtMediaEngine::Downloader.new

    error = assert_raises(YtMediaEngine::Error) { downloader.download("  ") }

    assert_match(/URL must be provided/, error.message)
  end

  # ---------------------------------------------------------------------------
  # #download — неизвестный формат
  # ---------------------------------------------------------------------------

  def test_download_raises_error_for_unknown_format
    downloader = YtMediaEngine::Downloader.new(format: :unknown)

    downloader.define_singleton_method(:fetch_metadata) { |_url| {} }

    error = assert_raises(YtMediaEngine::Error) { downloader.download(URL) }

    assert_match(/Unknown format/, error.message)
  end

  # ---------------------------------------------------------------------------
  # #cookies_args
  # ---------------------------------------------------------------------------

  def test_cookies_args_returns_empty_array_when_no_cookies
    downloader = YtMediaEngine::Downloader.new

    assert_equal [], downloader.send(:cookies_args),
                 "Без cookies файла должен возвращаться пустой массив"
  end

  def test_cookies_args_uses_file_when_provided
    cookies_file = create_temp_file("test cookies", ".txt")
    downloader   = YtMediaEngine::Downloader.new(cookies_path: cookies_file)

    assert_equal ["--cookies", File.expand_path(cookies_file)],
                 downloader.send(:cookies_args),
                 "Должен быть передан флаг --cookies с путём к файлу"
  end

  # ---------------------------------------------------------------------------
  # #format_args
  # ---------------------------------------------------------------------------

  def test_format_args_for_audio
    downloader = YtMediaEngine::Downloader.new(format: :audio, audio_format: "mp3", quality: "best")
    args       = downloader.send(:format_args)

    assert_includes args, "--extract-audio", "Должен быть флаг --extract-audio"
    assert_includes args, "--audio-format",  "Должен быть флаг --audio-format"
    assert_equal "mp3", args[args.index("--audio-format") + 1],
                 "Должен быть указан формат mp3"
  end

  def test_format_args_for_video
    downloader = YtMediaEngine::Downloader.new(format: :video, video_format: "mp4")
    args       = downloader.send(:format_args)

    assert_includes args, "--merge-output-format", "Должен быть флаг --merge-output-format"
    assert_equal "mp4", args[args.index("--merge-output-format") + 1],
                 "Должен быть указан формат mp4"
  end

  def test_quality_param_passed_to_yt_dlp
    downloader = YtMediaEngine::Downloader.new(format: :audio, quality: "worstaudio")
    args       = downloader.send(:format_args)

    f_index = args.index("-f")
    refute_nil f_index, "Флаг -f должен присутствовать"
    assert_equal "worstaudio", args[f_index + 1],
                 "Quality параметр должен передаваться в -f"
  end

  # ---------------------------------------------------------------------------
  # #extract_thumbnail_url
  # ---------------------------------------------------------------------------

  def test_extract_thumbnail_url_chooses_largest
    downloader = YtMediaEngine::Downloader.new
    metadata   = {
      "thumbnails" => [
        { "url" => "small.jpg",  "width" => 100, "height" => 100 },
        { "url" => "large.jpg",  "width" => 500, "height" => 500 },
        { "url" => "medium.jpg", "width" => 200, "height" => 200 }
      ]
    }

    assert_equal "large.jpg", downloader.send(:extract_thumbnail_url, metadata),
                 "Должен выбрать самую большую превьюшку"
  end

  def test_extract_thumbnail_url_returns_nil_on_error
    downloader = YtMediaEngine::Downloader.new
    metadata   = { "thumbnails" => "not an array" }

    assert_nil downloader.send(:extract_thumbnail_url, metadata),
               "При ошибке должен возвращаться nil"
  end

  def test_extract_thumbnail_url_returns_nil_when_no_thumbnails
    downloader = YtMediaEngine::Downloader.new
    metadata   = { "thumbnails" => [] }

    assert_nil downloader.send(:extract_thumbnail_url, metadata),
               "При пустом массиве должен возвращаться nil"
  end

  # ---------------------------------------------------------------------------
  # #initialize создаёт output_dir
  # ---------------------------------------------------------------------------

  def test_initialize_creates_output_dir
    test_dir = "tmp/test_initialize_dir"
    FileUtils.rm_rf(test_dir)

    refute Dir.exist?(test_dir), "Директория не должна существовать до теста"

    YtMediaEngine::Downloader.new(output_dir: test_dir)

    assert Dir.exist?(test_dir), "Директория #{test_dir} должна быть создана"
  ensure
    FileUtils.rm_rf(test_dir)
  end

  # ---------------------------------------------------------------------------
  # #yt_dlp_env
  # ---------------------------------------------------------------------------

  def test_yt_dlp_env_returns_hash_with_ffmpeg_path
    ffmpeg_path = "/custom/path/ffmpeg"
    downloader  = YtMediaEngine::Downloader.new(ffmpeg_path: ffmpeg_path)

    assert_equal({ "FFMPEG_BINARY" => ffmpeg_path }, downloader.send(:yt_dlp_env))
  end

  # ---------------------------------------------------------------------------
  # #run_with_timeout
  # ---------------------------------------------------------------------------

  def test_run_with_timeout_raises_error_on_timeout
    downloader = YtMediaEngine::Downloader.new

    cmd = RUBY_PLATFORM =~ /mingw|mswin/ ? ["ping", "-n", "10", "127.0.0.1"] : ["sleep", "10"]

    error = assert_raises(YtMediaEngine::Error) do
      downloader.send(:run_with_timeout, cmd, 1)
    end

    assert_match(/timed out/, error.message)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  private

  def create_temp_file(content = "test", extension = ".txt")
    FileUtils.mkdir_p("tmp/test")
    path = "tmp/test/temp_#{Time.now.to_i}_#{rand(1000)}#{extension}"
    File.write(path, content)
    @temp_files << path
    path
  end

  def cleanup_temp_files
    FileUtils.rm_rf("tmp/test")
  end
end