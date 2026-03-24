require "telegram/bot"
require "redis"
require "dotenv/load"
require_relative "AdditionalFunctions"
require_relative "Worker"

redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
TOKEN = ENV['TELEGRAM_TOKEN']

Telegram::Bot::Client.run(TOKEN) do |bot|
  bot.listen do |message|
    case message
    when Telegram::Bot::Types::Message
      if (valid_youtube_link?(message) && youtube_video_exists?(message, "AIzaSyBbB4Rs7TQTSzVDQXNgKr0AVnXuBoaA6iA")) | valid_rutube_link?(message)
        redis.set("user_url_#{message.chat.id}", message.text)
        redis.expire("user_url_#{message.chat.id}", 3600)

        bot.api.send_message(chat_id: message.chat.id, text: 'Select the format:', reply_markup: initial_keyboard)
      end
    when Telegram::Bot::Types::CallbackQuery
      chat_id = message.message.chat.id
      url = redis.get("user_url_#{chat_id}")

      case message.data
      when "form_vid"
        bot.api.send_message(chat_id: chat_id, text: "Выберите разрешение:", reply_markup: video_quality_keyboard)

      when "form_aud"
        bot.api.send_message(chat_id: chat_id, text: "Выберите формат аудио:", reply_markup: audio_format_keyboard)

      when "form_prev"
        VideoWorker.perform_async(chat_id, url, "preview")

      when /^vid_(\d+)$/  # например vid_720
        quality = $1
        bot.api.send_message(chat_id: chat_id, text: "Задача добавлена! Обрабатываю видео #{quality}p...")
        VideoWorker.perform_async(chat_id, url, "video", quality)

      when /^aud_(\w+)$/  # например aud_mp3
        format = $1
        bot.api.send_message(chat_id: chat_id, text: "Задача добавлена! Обрабатываю аудио (#{format})...")
        VideoWorker.perform_async(chat_id, url, "audio", format)
      end
    end
  end
end