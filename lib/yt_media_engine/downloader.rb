require "open3"
require "json"
require "securerandom"
require "fileutils"
require "timeout"

module YtMediaEngine
  class Error < StandardError; end

  class Downloader
    DEFAULT_OUTPUT_DIR = File.expand_path("tmp/yt_media_engine", Dir.pwd)
    DOWNLOAD_TIMEOUT   = 300

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
            ] + cookies_args + [url]

      stdout, _stderr, status = run_with_timeout(cmd, 60)
      return {} unless status.success?

      JSON.parse(stdout.force_encoding("UTF-8").scrub.strip)
    rescue JSON::ParserError, Timeout::Error
      {}
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
            ] + cookies_args + format_args + [url]

      _stdout, stderr, status = run_with_timeout(cmd, DOWNLOAD_TIMEOUT)

      unless status.success?
        raise Error, "yt-dlp failed (status=#{status.exitstatus}): #{stderr.force_encoding('UTF-8').scrub.strip}"
      end
    end

    def format_args
      case @format
      when :audio
        # bestaudio/best — fallback на best если отдельного аудио нет
        ["-f", (@quality || "bestaudio/best"),
         "--extract-audio", "--audio-format", @audio_format]
      when :video
        # Цепочка fallback-ов: сначала лучшее видео+аудио вместе,
        # потом просто лучшее что есть, потом вообще что угодно
        ["-f", (@quality || "bestvideo+bestaudio/bestvideo/best"),
         "--merge-output-format", "mp4"]
      else
        raise Error, "Unknown format #{@format.inspect} (use :audio or :video)"
      end
    end

    def run_with_timeout(cmd, timeout_sec)
      stdout_buf = +""
      stderr_buf = +""
      status     = nil

      Timeout.timeout(timeout_sec) do
        Open3.popen3(yt_dlp_env, *cmd) do |_stdin, stdout, stderr, wait_thr|
          t1 = Thread.new { stdout_buf << stdout.read }
          t2 = Thread.new { stderr_buf << stderr.read }
          t1.join
          t2.join
          status = wait_thr.value
        end
      end

      [stdout_buf, stderr_buf, status]
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