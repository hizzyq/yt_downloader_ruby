require "telegram/bot"
require_relative 'AdditionalFunctions'

TOKEN = "8755759006:AAE6DbUxmXpSd67WlxnFes_OK4bpkkH-A0M"

Telegram::Bot::Client.run(TOKEN) do |bot|
  bot.listen do |message|
    case message
    when Telegram::Bot::Types::Message
      if valid_youtube_link?(message.text)
        kb = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: [
            [
              Telegram::Bot::Types::InlineKeyboardButton.new(text: "Video", callback_data: "form_vid"),
              Telegram::Bot::Types::InlineKeyboardButton.new(text: "Audio", callback_data: "form_aud"),
              Telegram::Bot::Types::InlineKeyboardButton.new(text: "Preview", callback_data: "form_prev")
            ]
          ]
        )
        bot.api.send_message(chat_id: message.chat.id, text: 'Select the format you want to convert the video to:', reply_markup: kb)
      else
        bot.api.send_message(chat_id: message.chat.id, text: 'I don\'t think this is a link to a YouTube video. Check it out.')
      end
    when Telegram::Bot::Types::CallbackQuery
      case message.data
      when "form_vid"
        # Вот тут короче задача должна отправиться в очередь
        # Пример: VideoWorker.perform_async(message.text, message.chat.id, "720p")
      when "form_aud"
        # И тут
      when "form_prev"
        # И тут мб хз я не разбираюсь я кнопочки делаю
      end
    end
  end
end