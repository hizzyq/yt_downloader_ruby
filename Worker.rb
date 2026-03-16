require "sidekiq"
require "telegram/bot"
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

  TELEGRAM_TIMEOUT = 120
  MAX_RETRIES      = 3

  def perform(chat_id, url, format_type)
    bot = build_bot
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
        send_with_retry(bot, :send_message,
                        chat_id: chat_id,
                        text: "❌ Файл слишком большой (#{file_size_mb.round(1)} МБ). Telegram разрешает не более 50 МБ."
        )
      else
        send_with_retry(bot, :send_message, chat_id: chat_id, text: "Файл готов! Отправляю в Telegram...")
        send_with_retry(bot, :send_document,
                        chat_id: chat_id,
                        document: Faraday::UploadIO.new(file_path, 'application/octet-stream')
        )
      end

      File.delete(file_path) if File.exist?(file_path)

    rescue => e
      begin
        bot.api.send_message(chat_id: chat_id, text: "Произошла ошибка при загрузке: #{e.message}")
      rescue
        # если даже сообщение об ошибке не отправить — просто логируем
        puts "FATAL: cannot reach Telegram for chat #{chat_id}: #{e.message}"
      end
    end
  end

  private

  def build_bot
    proxy = ENV['PROXY_URL']
    options = { read_timeout: TELEGRAM_TIMEOUT, open_timeout: TELEGRAM_TIMEOUT }

    if proxy
      Telegram::Bot::Client.new(ENV['TELEGRAM_TOKEN'],
                                adapter: :net_http_proxy,
                                proxy: proxy,
                                **options
      )
    else
      Telegram::Bot::Client.new(ENV['TELEGRAM_TOKEN'], **options)
    end
  end

  def send_with_retry(bot, method, **params)
    attempts = 0
    begin
      attempts += 1
      bot.api.public_send(method, **params)
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      retry if attempts < MAX_RETRIES
      raise e
    end
  end
end