require "open3"
require "json"
require "securerandom"
require "fileutils"
require "timeout"

module YtMediaEngine
  class Error < StandardError; end

  class Downloader
    DEFAULT_OUTPUT_DIR = File.expand_path("tmp/yt_media_engine", Dir.pwd)
    DOWNLOAD_TIMEOUT   = 120

    def self.download(url, **options)
      new(**options).download(url)
    end

    def initialize(
      format: :audio,
      audio_format: "mp3",
      video_format: "mp4",
      quality: nil,
      output_dir: DEFAULT_OUTPUT_DIR,
      yt_dlp_path: "yt-dlp",
      ffmpeg_path: "ffmpeg",
      cookies_path: nil
    )
      @format       = format&.to_sym
      @audio_format = audio_format
      @video_format = video_format
      @quality      = quality&.to_s&.strip
      @output_dir   = File.expand_path(output_dir.to_s)
      @yt_dlp_path  = yt_dlp_path
      @ffmpeg_path  = ffmpeg_path
      @cookies_path = cookies_path && File.expand_path(cookies_path.to_s)
      @proxy_url = ENV['PROXY_URL']

      FileUtils.mkdir_p(@output_dir)
    end

    def download(url)
      raise Error, "URL must be provided" if url.to_s.strip.empty?

      tmp_dir = File.join(@output_dir, SecureRandom.uuid)
      FileUtils.mkdir_p(tmp_dir)

      metadata = fetch_metadata(url)
      run_download(url, tmp_dir)

      file_path      = pick_downloaded_file(tmp_dir)
      thumbnail_path = find_thumbnail_file(tmp_dir)

      raise Error, "Downloaded file not found in #{tmp_dir}" unless file_path

      {
        path:           file_path,
        title:          metadata["title"],
        thumbnail_url:  extract_thumbnail_url(metadata),
        thumbnail_path: thumbnail_path,
        raw_metadata:   metadata
      }
    end

    private

    def proxy_args
      return [] if @proxy_url.to_s.strip.empty?
      ["--proxy", @proxy_url]
    end

    def cookies_args
      return [] unless @cookies_path && File.file?(@cookies_path) && File.size(@cookies_path) > 0
      ["--cookies", @cookies_path]
    end

    def yt_dlp_env
      { "FFMPEG_BINARY" => @ffmpeg_path }
    end

    def fetch_metadata(url)
      cmd = [
              @yt_dlp_path,
              "--no-playlist",
              "--dump-json",
              "--no-warnings",
              "--force-ipv4"
            ] + cookies_args + proxy_args + [url]

      stdout, _stderr, status = run_with_timeout(cmd, 60)
      return {} unless status&.success?

      JSON.parse(stdout.force_encoding("UTF-8").scrub.strip)
    rescue JSON::ParserError => e
      raise Error, "Failed to parse yt-dlp metadata JSON: #{e.message}"
    end

    def run_download(url, tmp_dir)
      cmd = [
              @yt_dlp_path,
              "--no-playlist",
              "--no-warnings",
              "--restrict-filenames",
              "--force-ipv4",
              "-o", File.join(tmp_dir, "%(title)s.%(ext)s"),
              "--write-thumbnail",
              "--convert-thumbnails", "jpg"
            ] + cookies_args + proxy_args + format_args + [url]

      _stdout, stderr, status = run_with_timeout(cmd, DOWNLOAD_TIMEOUT)

      unless status.success?
        raise Error, "yt-dlp failed (status=#{status.exitstatus}): #{stderr.force_encoding('UTF-8').scrub.strip}"
      end
    end

    def format_args
      case @format
      when :audio
        # bestaudio → потом лучшее что есть с перекодированием
        audio_format_string = @quality || "bestaudio/best"
        [
          "-f", audio_format_string,
          "--extract-audio",
          "--audio-format", @audio_format,
          "--audio-quality", "0"   # лучшее качество при перекодировании
        ]

      when :video
        ["-f", video_format_string, "--merge-output-format", "mp4"]

      when :preview
        # Только метаданные и миниатюра — само видео не качаем
        ["--skip-download"]

      else
        raise Error, "Unknown format #{@format.inspect} (use :audio, :video or :preview)"
      end
    end

    # Строит правильную строку формата для yt-dlp с fallback-цепочкой
    #
    # Примеры результата:
    #   quality="1080" → "bestvideo[height<=1080]+bestaudio/bestvideo[height<=1080]/best[height<=1080]/bestvideo+bestaudio/best"
    #   quality=nil    → "bestvideo+bestaudio/bestvideo/best"
    def video_format_string
      if @quality && @quality =~ /\A\d+\z/
        h = @quality.to_i
        # Цепочка с постепенным снижением требований:
        # 1. Отдельные видео+аудио треки нужного качества (требует ffmpeg для merge)
        # 2. Один трек (progressive) нужного качества
        # 3. Лучшее что есть с нужным качеством (без ограничения на codec)
        # 4. Просто лучшее без ограничений — последний fallback
        "bestvideo[height<=#{h}][ext=mp4]+bestaudio[ext=m4a]" \
          "/bestvideo[height<=#{h}]+bestaudio" \
          "/best[height<=#{h}]" \
          "/bestvideo+bestaudio" \
          "/best"
      else
        # Качество не указано — берём максимум
        "bestvideo[ext=mp4]+bestaudio[ext=m4a]/bestvideo+bestaudio/best"
      end
    end

    def run_with_timeout(cmd, timeout_sec)
      stdout, stderr, status = nil

      Timeout.timeout(timeout_sec) do
        stdout, stderr, status = Open3.capture3(yt_dlp_env, *cmd)
      end

      [stdout, stderr, status]
    rescue Timeout::Error
      raise Error, "yt-dlp timed out after #{timeout_sec}s"
    end

    def pick_downloaded_file(dir)
      sleep 0.5
      candidates = Dir[File.join(dir, "*")].select { |p| File.file?(p) }
      candidates.reject! do |p|
        File.extname(p).downcase =~ /\.(jpg|jpeg|png|webp|json|part|ytdl)$/
      end
      candidates.max_by { |p| File.mtime(p) }
    end

    def find_thumbnail_file(dir)
      Dir[File.join(dir, "*.{jpg,jpeg,png,webp}")].max_by { |p| File.mtime(p) }
    end

    def extract_thumbnail_url(metadata)
      thumbs = metadata["thumbnails"]
      return nil unless thumbs.is_a?(Array) && !thumbs.empty?
      thumbs.max_by { |t| t["width"].to_i * t["height"].to_i }&.fetch("url", nil)
    rescue
      nil
    end
  end
end