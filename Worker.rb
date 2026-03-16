require "sidekiq"
require "telegram/bot"
require "dotenv/load"
require_relative "lib/yt_media_engine"

# Настройка Sidekiq
Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0') }
end
Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0') }
end

class VideoWorker
  include Sidekiq::Worker
  sidekiq_options retry: false

  def perform(chat_id, url, format_type)
    proxy = ENV['PROXY_URL']
    bot = if proxy
            Telegram::Bot::Client.new(ENV['TELEGRAM_TOKEN'], adapter: :net_http_proxy, proxy: proxy)
          else
            Telegram::Bot::Client.new(ENV['TELEGRAM_TOKEN'])
          end
    begin
      bot.api.send_message(chat_id: chat_id, text: "Скачиваю #{format_type}... Это может занять время.")

      downloader = YtMediaEngine::Downloader.new(
        format: format_type.to_sym,
        output_dir: "/app/tmp/yt_media_engine",
        cookies_path: "/app/cookies.txt"
      )

      result = downloader.download(url)
      file_path = result[:path]

      file_size_mb = File.size(file_path).to_f / (1024 * 1024)

      if file_size_mb > 50
        bot.api.send_message(
          chat_id: chat_id,
          text: "❌ Ошибка: Файл слишком большой (#{file_size_mb.round(1)} МБ). Telegram разрешает отправлять ботам файлы не более 50 МБ."
        )
      else
        bot.api.send_message(chat_id: chat_id, text: "Файл готов! Отправляю в Telegram...")

        bot.api.send_document(
          chat_id: chat_id,
          document: Faraday::UploadIO.new(file_path, 'application/octet-stream')
        )
      end

      File.delete(file_path) if File.exist?(file_path)

    rescue => e
      bot.api.send_message(chat_id: chat_id, text: "Произошла ошибка при загрузке: #{e.message}")
    end
  end
end