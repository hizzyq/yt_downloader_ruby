require "open3"
require "json"
require "securerandom"
require "fileutils"

module YtMediaEngine
  class Error < StandardError; end

  class Downloader
    DEFAULT_OUTPUT_DIR = File.expand_path("tmp/yt_media_engine", Dir.pwd)

    # options:
    #   :format        - :audio or :video (default :audio)
    #   :audio_format  - mp3, m4a, etc (for :audio, default "mp3")
    #   :video_format  - mp4, mkv, etc (for :video, default "mp4")
    #   :quality       - yt-dlp format string, e.g. "bestaudio/best"
    #   :output_dir    - directory to put resulting files
    #   :yt_dlp_path   - custom path to yt-dlp binary
    #   :ffmpeg_path   - custom path to ffmpeg binary
    #   :cookies_path  - path to cookies.txt file for authenticated downloads
    #
    # Returns hash:
    #   {
    #     path: "/absolute/path/to/file",
    #     title: "Video title",
    #     thumbnail_url: "https://...",
    #     thumbnail_path: "/absolute/path/to/thumbnail_or_nil",
    #     raw_metadata: {...} # yt-dlp JSON
    #   }
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
      @quality      = quality
      @output_dir   = File.expand_path(output_dir.to_s)
      @yt_dlp_path  = yt_dlp_path
      @ffmpeg_path  = ffmpeg_path
      @cookies_path = cookies_path && File.expand_path(cookies_path.to_s)

      FileUtils.mkdir_p(@output_dir)
    end

    def download(url)
      raise Error, "URL must be provided" if url.to_s.strip.empty?

      tmp_dir = File.join(@output_dir, SecureRandom.uuid)
      FileUtils.mkdir_p(tmp_dir)

      yt_dlp_cmd = build_yt_dlp_command(url, tmp_dir)

      stdout_str, stderr_str, status = Open3.capture3(yt_dlp_env, *yt_dlp_cmd)

      stdout_str = stdout_str.force_encoding('UTF-8').scrub
      stderr_str = stderr_str.force_encoding('UTF-8').scrub

      unless status.success?
        raise Error, "yt-dlp failed (status=#{status.exitstatus}): #{stderr_str.strip}"
      end

      metadata = parse_metadata(stdout_str)
      file_path = pick_downloaded_file(tmp_dir)
      thumbnail_path = find_thumbnail_file(tmp_dir)

      raise Error, "Downloaded file not found in #{tmp_dir}" unless file_path

      {
        path: file_path,
        title: metadata["title"],
        thumbnail_url: extract_thumbnail_url(metadata),
        thumbnail_path: thumbnail_path,
        raw_metadata: metadata
      }
    ensure
      # leave tmp_dir with media & thumbnail in place for caller
    end

    private

    def yt_dlp_env
      {
        "FFMPEG_BINARY" => @ffmpeg_path
      }
    end

    def build_yt_dlp_command(url, tmp_dir)
      base = [
        @yt_dlp_path,
        "--no-playlist",
        "--no-warnings",
        "--restrict-filenames",
        "--ignore-errors",
        "--print", "%(infojson)s",
        "-o", File.join(tmp_dir, "%(title)s.%(ext)s"),
        "--write-thumbnail",
        "--convert-thumbnails", "jpg"
      ]

      # authenticated cookies file (avoids DPAPI / --cookies-from-browser issues inside Docker)
      if @cookies_path
        base += ["--cookies", @cookies_path]
      end

      case @format
      when :audio
        # Сначала указываем качество через -f, потом команды конвертации
        base += ["-f", (@quality || "bestaudio/best")]
        base += ["--extract-audio", "--audio-format", @audio_format]
      when :video
        base += ["-f", (@quality || "bestvideo*+bestaudio/best")]
      else
        raise Error, "Unknown format #{@format.inspect} (use :audio or :video)"
      end

      (base + [url]).flatten
    end

    def parse_metadata(stdout_str)
      # stdout may contain extra lines; find JSON line
      json_line = stdout_str.lines.find { |l| l.strip.start_with?("{") && l.strip.end_with?("}") }
      JSON.parse(json_line || "{}")
    rescue JSON::ParserError => e
      raise Error, "Failed to parse yt-dlp metadata JSON: #{e.message}"
    end

    def pick_downloaded_file(dir)
      # Даем Windows 0.5 секунды, чтобы завершить запись файла на диск
      sleep 0.5

      # Получаем все файлы в директории
      candidates = Dir[File.join(dir, "*")].select { |p| File.file?(p) }

      # Убираем картинки, JSON-метаданные и временные файлы самого yt-dlp
      candidates.reject! do |p|
        ext = File.extname(p).downcase
        ext =~ /\.(jpg|jpeg|png|webp|json|part|ytdl)$/
      end

      # Если файлов несколько, берем самый новый (по времени изменения)
      candidates.max_by { |p| File.mtime(p) }
    end

    def find_thumbnail_file(dir)
      thumbs = Dir[File.join(dir, "*.{jpg,jpeg,png,webp}")]
      thumbs.max_by { |p| File.mtime(p) }
    end

    def extract_thumbnail_url(metadata)
      thumbs = metadata["thumbnails"]
      return nil unless thumbs.is_a?(Array) && !thumbs.empty?

      (thumbs.max_by { |t| t["width"].to_i * t["height"].to_i })["url"]
    rescue
      nil
    end
  end
end

