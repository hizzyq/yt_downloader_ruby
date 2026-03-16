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
      if valid_youtube_link?(message.text)
        redis.set("user_url_#{message.chat.id}", message.text)
        redis.expire("user_url_#{message.chat.id}", 3600)

        kb = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: [
          [
            Telegram::Bot::Types::InlineKeyboardButton.new(text: "Video", callback_data: "form_vid"),
            Telegram::Bot::Types::InlineKeyboardButton.new(text: "Audio", callback_data: "form_aud")
          ]
        ])
        bot.api.send_message(chat_id: message.chat.id, text: 'Select the format:', reply_markup: kb)
      else
        bot.api.send_message(chat_id: message.chat.id, text: 'I don\'t think this is a link to a YouTube video. Check it out.')
      end

    when Telegram::Bot::Types::CallbackQuery
      url = redis.get("user_url_#{message.message.chat.id}")
      if url
        bot.api.send_message(chat_id: message.message.chat.id, text: "Задача добавлена в очередь! Начинаю обработку...")

        format_type = message.data == "form_vid" ? "video" : "audio"
        VideoWorker.perform_async(message.message.chat.id, url, format_type)
      else
        bot.api.send_message(chat_id: message.message.chat.id, text: "Ссылка устарела или потеряна. Отправьте видео заново.")
      end
    end
  end
end