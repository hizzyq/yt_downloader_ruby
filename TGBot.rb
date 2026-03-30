require "telegram/bot"
require "redis"
require "dotenv/load"
require "logger"
require_relative "AdditionalFunctions"
require_relative "Worker"

logger = Logger.new(STDOUT)
logger.level = Logger::INFO

redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
TOKEN = ENV['TELEGRAM_TOKEN']

logger.info("Bot is starting...")

Thread.new do
  loop do
    _list, event_json = redis.brpop("bot_events", timeout: 5)
    if event_json
      begin
        event = JSON.parse(event_json)
        chat_id = event["chat_id"]
        
        case event["type"]
        when "status"
          Telegram::Bot::Api.new(TOKEN).send_message(chat_id: chat_id, text: event["text"])
        when "send_file"
          file_path = event["file_path"]
          logger.info("Received file from worker for chat_id #{chat_id}. File path: #{file_path}")
          
          # Отправка файла
          if File.exist?(file_path)
            begin
              logger.info("Sending file to chat_id #{chat_id}...")
              api = Telegram::Bot::Api.new(TOKEN)
              
              if file_path.end_with?('.mp4') || file_path.end_with?('.webm')
                api.send_video(chat_id: chat_id, video: Faraday::UploadIO.new(file_path, 'video/mp4'))
              elsif file_path.end_with?('.mp3') || file_path.end_with?('.m4a') || file_path.end_with?('.wav')
                api.send_audio(chat_id: chat_id, audio: Faraday::UploadIO.new(file_path, 'audio/mpeg'))
              else
                api.send_document(chat_id: chat_id, document: Faraday::UploadIO.new(file_path, 'application/octet-stream'))
              end
              
              logger.info("File sent successfully to chat_id #{chat_id}. Cleaning up...")
              File.delete(file_path) # Удаляем после успешной отправки
            rescue => e
              logger.error("Error sending file to chat_id #{chat_id}: #{e.message}")
              Telegram::Bot::Api.new(TOKEN).send_message(chat_id: chat_id, text: "❌ Ошибка при отправке файла: #{e.message}")
            end
          else
            logger.error("File not found for chat_id #{chat_id}: #{file_path}")
            Telegram::Bot::Api.new(TOKEN).send_message(chat_id: chat_id, text: "❌ Ошибка: файл не найден воркером по пути #{file_path}.")
          end
        end
      rescue => e
        logger.error("Error processing event from worker: #{e.message}")
      end
    end
  end
end

Telegram::Bot::Client.run(TOKEN) do |bot|
  bot.listen do |message|
    case message
    when Telegram::Bot::Types::Message
      if (valid_youtube_link?(message.text) && youtube_video_exists?(message.text, "AIzaSyBbB4Rs7TQTSzVDQXNgKr0AVnXuBoaA6iA")) | valid_rutube_link?(message.text)
      logger.info("Received message from chat_id #{message.chat.id}: #{message.text}")
        redis.set("user_url_#{message.chat.id}", message.text)
        redis.expire("user_url_#{message.chat.id}", 3600)

        bot.api.send_message(chat_id: message.chat.id, text: 'Select the format:', reply_markup: initial_keyboard)
      else
        logger.info("Invalid or unsupported link from chat_id #{message.chat.id}")
      end
    when Telegram::Bot::Types::CallbackQuery
      chat_id = message.message.chat.id
      url = redis.get("user_url_#{chat_id}")
      logger.info("Received callback query from chat_id #{chat_id}: #{message.data}")

      case message.data
      when "form_vid"
        bot.api.send_message(chat_id: chat_id, text: "Выберите разрешение:", reply_markup: video_quality_keyboard)

      when "form_aud"
        bot.api.send_message(chat_id: chat_id, text: "Выберите формат аудио:", reply_markup: audio_format_keyboard)

      when "form_prev"
        logger.info("Enqueueing preview task for chat_id #{chat_id} (url: #{url})")
        VideoWorker.perform_async(chat_id, url, "preview")

      when /^vid_(\d+)$/  # например vid_720
        quality = $1
        logger.info("Enqueueing video task #{quality}p for chat_id #{chat_id} (url: #{url})")
        bot.api.send_message(chat_id: chat_id, text: "Задача добавлена! Обрабатываю видео #{quality}p...")
        VideoWorker.perform_async(chat_id, url, "video", quality)

      when /^aud_(\w+)$/  # например aud_mp3
        format = $1
        logger.info("Enqueueing audio task #{format} for chat_id #{chat_id} (url: #{url})")
        bot.api.send_message(chat_id: chat_id, text: "Задача добавлена! Обрабатываю аудио (#{format})...")
        VideoWorker.perform_async(chat_id, url, "audio", format)
      end
    end
  end
end
