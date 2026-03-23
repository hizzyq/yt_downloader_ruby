require 'net/http'
require 'json'

def youtube_video_exists?(video_id, api_key)
  url = URI("https://www.googleapis.com/youtube/v3/videos?id=#{video_id}&part=status&key=#{api_key}")
  response = Net::HTTP.get(url)
  data = JSON.parse(response)

  return false if data["pageInfo"]["totalResults"] == 0

  status = data["items"][0]["status"]

  return false if status["privacyStatus"] == "private"
  return false if status["uploadStatus"] != "processed"

  true
end

def url?(text)
  text =~ /\Ahttps?:\/\/\S+\z/
end

def youtube_video?(text)
  text =~ %r{
    (youtu\.be\/[\w-]+)|
    (youtube\.com\/watch\?v=[\w-]+)|
    (youtube\.com\/shorts\/[\w-]+)|
    (youtube\.com\/embed\/[\w-]+)
  }x
end

def rutube_video?(text)
  text =~ %r{
    rutube\.ru\/video\/[\w-]{20,} |   # обычная ссылка на видео
    rutube\.ru\/pl\/[\w-]{20,}        # короткая ссылка
  }x
end

def valid_youtube_link?(text)
  url?(text) && youtube_video?(text)
end

def valid_rutube_link?(text)
  url?(text) && rutube_video?(text)
end

def initial_keyboard
  Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: [
    [
      Telegram::Bot::Types::InlineKeyboardButton.new(text: "Video", callback_data: "form_vid"),
      Telegram::Bot::Types::InlineKeyboardButton.new(text: "Audio", callback_data: "form_aud"),
      Telegram::Bot::Types::InlineKeyboardButton.new(text: "Preview", callback_data: "form_prev")
    ]
  ])
end

def audio_format_keyboard
  Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: [
    [
      Telegram::Bot::Types::InlineKeyboardButton.new(text: "MP3", callback_data: "aud_mp3"),
      Telegram::Bot::Types::InlineKeyboardButton.new(text: "WAV", callback_data: "aud_wav"),
      Telegram::Bot::Types::InlineKeyboardButton.new(text: "OGG", callback_data: "aud_ogg")
    ]
  ])
end

def video_quality_keyboard
  Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: [
    [
      Telegram::Bot::Types::InlineKeyboardButton.new(text: "1080p", callback_data: "vid_1080"),
      Telegram::Bot::Types::InlineKeyboardButton.new(text: "720p", callback_data: "vid_720"),
      Telegram::Bot::Types::InlineKeyboardButton.new(text: "480p", callback_data: "vid_480"),
      Telegram::Bot::Types::InlineKeyboardButton.new(text: "360p", callback_data: "vid_360")
    ]
  ])
end