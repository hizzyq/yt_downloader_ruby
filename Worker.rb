require "sidekiq"
require "redis"
require "dotenv/load"
require_relative "lib/yt_media_engine"

Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0') }
end
Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0') }
end

class VideoWorker
  include Sidekiq::Worker
  sidekiq_options retry: false

  def perform(chat_id, url, format_type, quality_or_format = nil)
    redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))

    # Уведомляем бота что задача начата
    push_event(redis, {
      type:    "status",
      chat_id: chat_id,
      text:    "⏳ Скачиваю #{format_type}... Это может занять время."
    })

    download_opts = {
      output_dir:   "/app/tmp/yt_media_engine",
      cookies_path: "/app/cookies.txt"
    }

    case format_type
    when "video"
      download_opts[:format]  = :video
      download_opts[:quality] = quality_or_format if quality_or_format
    when "audio"
      download_opts[:format]       = :audio
      download_opts[:audio_format] = quality_or_format if quality_or_format
    when "preview"
      download_opts[:format] = :preview
    else
      download_opts[:format] = format_type.to_sym
    end

    downloader = YtMediaEngine::Downloader.new(**download_opts)
    result     = downloader.download(url)
    file_path  = result[:path]

    unless File.exist?(file_path)
      push_event(redis, {
        type:    "status",
        chat_id: chat_id,
        text:    "❌ Файл не был создан. Проверьте ссылку."
      })
      return
    end

    file_size_mb = File.size(file_path).to_f / (1024 * 1024)

    if file_size_mb > 50
      push_event(redis, {
        type:    "status",
        chat_id: chat_id,
        text:    "❌ Файл слишком большой (#{file_size_mb.round(1)} МБ). Telegram разрешает не более 50 МБ."
      })
      File.delete(file_path) if File.exist?(file_path)
    else
      # Файл готов — бот сам заберёт и отправит через своё соединение
      push_event(redis, {
        type:      "send_file",
        chat_id:   chat_id,
        file_path: file_path
      })
    end

  rescue => e
    puts "ERROR in VideoWorker for chat #{chat_id}: #{e.class} — #{e.message}"
    puts e.backtrace.first(5).join("\n")

    begin
      push_event(redis, {
        type:    "status",
        chat_id: chat_id,
        text:    "❌ Ошибка при загрузке: #{e.message}"
      })
    rescue => redis_err
      puts "FATAL: не могу записать ошибку в Redis: #{redis_err.message}"
    end
  end

  private

  def push_event(redis, payload)
    redis.lpush("bot_events", JSON.generate(payload))
  end
end
