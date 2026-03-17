# test/downloader_test.rb

require_relative "test_helper"
require_relative "../lib/yt_media_engine"

class DownloaderTest < TestCase
  include TestHelpers

  URL = "https://www.youtube.com/watch?v=E9T78bT26sk"

  def setup
    @original_new = YtMediaEngine::Downloader.method(:new)
  end

  def teardown
    cleanup_temp_files
    # Восстанавливаем оригинальный метод, если был изменен
    if @new_was_stubbed
      YtMediaEngine::Downloader.define_singleton_method(:new, @original_new)
    end
  end

  def test_class_download_delegates_to_instance
    dummy_result = { path: "/tmp/file.mp3" }

    # Правильный способ подмены метода класса
    @new_was_stubbed = true

    # Создаем объект-заглушку
    mock_downloader = Object.new
    def mock_downloader.download(url)
      { path: "/tmp/file.mp3" }
    end

    # Подменяем метод new через define_singleton_method
    YtMediaEngine::Downloader.define_singleton_method(:new) do |**opts|
      mock_downloader
    end

    result = YtMediaEngine::Downloader.download(URL, format: :audio)

    assert_equal(dummy_result[:path], result[:path],
                 "Метод .download должен возвращать результат экземпляра")
  end

  def test_download_raises_error_when_url_blank
    downloader = YtMediaEngine::Downloader.new

    error = assert_raises(YtMediaEngine::Error) do
      downloader.download("  ")
    end

    assert_match(/URL must be provided/, error.message)
  end

  def test_download_raises_error_for_unknown_format
    downloader = YtMediaEngine::Downloader.new(format: :unknown)

    # Подменяем метод экземпляра
    def downloader.fetch_metadata(url)
      {}
    end

    error = assert_raises(YtMediaEngine::Error) do
      downloader.download(URL)
    end

    assert_match(/Unknown format/, error.message)
  end

  def test_cookies_args_returns_empty_array_when_no_cookies
    downloader = YtMediaEngine::Downloader.new

    result = downloader.send(:cookies_args)
    assert_equal([], result, "Без cookies файла должен возвращаться пустой массив")
  end

  def test_cookies_args_uses_file_when_provided
    cookies_file = create_temp_file("test cookies", ".txt")

    downloader = YtMediaEngine::Downloader.new(cookies_path: cookies_file)

    args = downloader.send(:cookies_args)

    assert_equal(["--cookies", File.expand_path(cookies_file)], args,
                 "Должен быть передан флаг --cookies с путём к файлу")
  end

  def test_format_args_for_audio
    downloader = YtMediaEngine::Downloader.new(
      format: :audio,
      audio_format: "mp3",
      quality: "best"
    )

    args = downloader.send(:format_args)

    assert(args.include?("--extract-audio"), "Должен быть флаг --extract-audio")
    assert(args.include?("--audio-format"), "Должен быть флаг --audio-format")

    format_index = args.index("--audio-format")
    assert_equal("mp3", args[format_index + 1], "Должен быть указан формат mp3")
  end

  def test_format_args_for_video
    downloader = YtMediaEngine::Downloader.new(
      format: :video,
      video_format: "mp4"
    )

    args = downloader.send(:format_args)

    assert(args.include?("--merge-output-format"), "Должен быть флаг --merge-output-format")

    format_index = args.index("--merge-output-format")
    assert_equal("mp4", args[format_index + 1], "Должен быть указан формат mp4")
  end

  def test_quality_param_passed_to_yt_dlp
    downloader = YtMediaEngine::Downloader.new(
      format: :audio,
      quality: "worstaudio"
    )

    args = downloader.send(:format_args)

    format_index = args.index("-f")
    assert(format_index, "Флаг -f должен присутствовать")

    quality_value = args[format_index + 1]
    assert_equal("worstaudio", quality_value, "Quality параметр должен передаваться в -f")
  end

  def test_extract_thumbnail_url_chooses_largest
    downloader = YtMediaEngine::Downloader.new

    metadata = {
      "thumbnails" => [
        { "url" => "small.jpg", "width" => 100, "height" => 100 },
        { "url" => "large.jpg", "width" => 500, "height" => 500 },
        { "url" => "medium.jpg", "width" => 200, "height" => 200 }
      ]
    }

    result = downloader.send(:extract_thumbnail_url, metadata)

    assert_equal("large.jpg", result, "Должен выбрать самую большую превьюшку")
  end

  def test_extract_thumbnail_url_returns_nil_on_error
    downloader = YtMediaEngine::Downloader.new

    metadata = { "thumbnails" => "not an array" }
    result = downloader.send(:extract_thumbnail_url, metadata)

    assert_equal(nil, result, "При ошибке должен возвращаться nil")
  end

  def test_extract_thumbnail_url_returns_nil_when_no_thumbnails
    downloader = YtMediaEngine::Downloader.new

    metadata = { "thumbnails" => [] }
    result = downloader.send(:extract_thumbnail_url, metadata)

    assert_equal(nil, result, "При пустом массиве должен возвращаться nil")
  end

  def test_initialize_creates_output_dir
    test_dir = "tmp/test_initialize_dir"

    FileUtils.rm_rf(test_dir)
    refute(Dir.exist?(test_dir), "Директория не должна существовать до теста")

    downloader = YtMediaEngine::Downloader.new(output_dir: test_dir)

    assert(Dir.exist?(test_dir), "Директория #{test_dir} должна быть создана")

    FileUtils.rm_rf(test_dir)
  end

  def test_yt_dlp_env_returns_hash_with_ffmpeg_path
    ffmpeg_path = "/custom/path/ffmpeg"
    downloader = YtMediaEngine::Downloader.new(ffmpeg_path: ffmpeg_path)

    env = downloader.send(:yt_dlp_env)

    assert_equal({ "FFMPEG_BINARY" => ffmpeg_path }, env)
  end

  def test_run_with_timeout_raises_error_on_timeout
    downloader = YtMediaEngine::Downloader.new

    # Команда, которая зависает (разная для Windows и Unix)
    cmd = if RUBY_PLATFORM =~ /mingw|mswin/
            ["ping", "-n", "10", "127.0.0.1"]
          else
            ["sleep", "10"]
          end

    error = assert_raises(YtMediaEngine::Error) do
      downloader.send(:run_with_timeout, cmd, 1) # Таймаут 1 секунда
    end

    assert_match(/timed out/, error.message)
  end
end