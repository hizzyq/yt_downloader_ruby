$stdout.sync = true

require "telegram/bot"
require "redis"
require "json"
require "dotenv/load"
require_relative "AdditionalFunctions"
require_relative "Worker"

redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
TOKEN           = ENV['TELEGRAM_TOKEN']
VALIDATION_TOKEN = ENV['YT_VAL_TOKEN']
proxy_url = ENV['PROXY_URL']

# Фоновый поток: читает события из Redis и отправляет сообщения/файлы в Telegram
# Это нужно потому что воркер не может сам достучаться до api.telegram.org
def start_event_loop(bot, redis)
  Thread.new do
    loop do
      begin
        # brpop ждёт до 2 секунд — не грузит CPU
        result = redis.brpop("bot_events", timeout: 2)
        next unless result

        event = JSON.parse(result[1])
        chat_id = event["chat_id"]

        case event["type"]
        when "status"
          bot.api.send_message(chat_id: chat_id, text: event["text"])

        when "send_file"
          file_path = event["file_path"]

          if File.exist?(file_path)
            bot.api.send_message(chat_id: chat_id, text: "✅ Файл готов! Отправляю...")
            File.open(file_path, "rb") do |f|
              bot.api.send_document(
                chat_id:  chat_id,
                document: Faraday::UploadIO.new(f, "application/octet-stream", File.basename(file_path))
              )
            end
            File.delete(file_path) if File.exist?(file_path)
          else
            bot.api.send_message(chat_id: chat_id, text: "❌ Файл не найден — возможно истёк срок хранения.")
          end
        end

      rescue => e
        puts "EVENT LOOP ERROR: #{e.class} — #{e.message}"
        puts e.backtrace.first(3).join("\n")
        sleep 1  # небольшая пауза чтобы не спамить логи при повторных ошибках
      end
    end
  end
end

proxy_opts = {}
if proxy_url && !proxy_url.strip.empty?
  proxy_opts[:proxy] = proxy_url
end

puts "=> Запуск бота через мост: #{proxy_url}"
Telegram::Bot::Client.run(TOKEN, **proxy_opts) do |bot|
  # Запускаем обработчик событий от воркера
  puts "Bot is up and running..."
  start_event_loop(bot, redis)

  bot.listen do |message|
    case message
    when Telegram::Bot::Types::Message
      next unless message.text
      puts "=> [Сообщение] От #{message.chat.id}: #{message.text}"
      text = message.text.strip

      is_youtube = valid_youtube_link?(text) && youtube_video_exists?(text, VALIDATION_TOKEN)
      is_rutube  = valid_rutube_link?(text)

      if is_youtube || is_rutube
        redis.set("user_url_#{message.chat.id}", text)
        redis.expire("user_url_#{message.chat.id}", 3600)

        bot.api.send_message(
          chat_id:      message.chat.id,
          text:         "✅ Ссылка принята! Выберите формат:",
          reply_markup: initial_keyboard
        )
      end

    when Telegram::Bot::Types::CallbackQuery
      chat_id = message.message.chat.id
      url     = redis.get("user_url_#{chat_id}")

      unless url
        bot.api.answer_callback_query(callback_query_id: message.id, text: "⚠️ Ссылка устарела, отправьте заново.")
        next
      end

      case message.data
      when "form_vid"
        bot.api.send_message(chat_id: chat_id, text: "Выберите разрешение:", reply_markup: video_quality_keyboard)

      when "form_aud"
        bot.api.send_message(chat_id: chat_id, text: "Выберите формат аудио:", reply_markup: audio_format_keyboard)

      when "form_prev"
        VideoWorker.perform_async(chat_id, url, "preview", nil)

      when /^vid_(\d+)$/
        quality = $1
        bot.api.send_message(chat_id: chat_id, text: "📥 Задача добавлена! Обрабатываю видео #{quality}p...")
        VideoWorker.perform_async(chat_id, url, "video", quality)

      when /^aud_(\w+)$/
        fmt = $1
        bot.api.send_message(chat_id: chat_id, text: "📥 Задача добавлена! Обрабатываю аудио (#{fmt})...")
        VideoWorker.perform_async(chat_id, url, "audio", fmt)
      end

      bot.api.answer_callback_query(callback_query_id: message.id)
    end
  end
end
