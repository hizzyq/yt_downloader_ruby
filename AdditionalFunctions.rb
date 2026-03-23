require 'net/http'
require 'json'

require 'net/http'
require 'json'
require 'uri'
require 'timeout'

def youtube_video_exists?(video_url, api_key)
  return true if api_key.nil? || api_key.strip.empty?
  video_id = extract_youtube_id(video_url)
  return false if video_id.nil?

  uri = URI("https://www.googleapis.com/youtube/v3/videos?id=#{video_id}&part=status&key=#{api_key}")
  proxy_url = ENV['PROXY_URL']

  begin
    response = Timeout.timeout(10) do
      if proxy_url && !proxy_url.strip.empty?
        p_uri = URI.parse(proxy_url)
        # Стандартный HTTP прокси работает в Ruby идеально
        http = Net::HTTP.new(uri.host, uri.port, p_uri.host, p_uri.port, p_uri.user, p_uri.password)
        http.use_ssl = true
        http.get(uri.request_uri)
      else
        Net::HTTP.get_response(uri)
      end
    end

    data = JSON.parse(response.body)

    return false if data["pageInfo"].nil?
    return false if data["pageInfo"]["totalResults"] == 0
    return false if data["items"].nil? || data["items"].empty?

    status = data["items"][0]["status"]
    return false if status["privacyStatus"] == "private"
    return false if status["uploadStatus"] != "processed"

    true
  rescue Timeout::Error
    puts "=> YouTube API timeout: превышено время ожидания ответа. Разрешаем загрузку."
    true
  rescue => e
    puts "=> YouTube API error: #{e.class} - #{e.message}"
    true # При любой сетевой ошибке не блокируем скачивание
  end
end

def extract_youtube_id(text)
  if text =~ /(?:youtu\.be\/|youtube\.com\/(?:watch\\?v=|shorts\/|embed\/))([\w-]+)/
    $1
  end
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
    rutube\.ru\/video\/[\w-]{20,} |
    rutube\.ru\/pl\/[\w-]{20,}    |
    rutube\.ru\/shorts\/[\w-]+
  }x
end

def valid_youtube_link?(text)
  return false if text.nil? || text.strip.empty?
  url?(text) && youtube_video?(text)
end

def valid_rutube_link?(text)
  return false if text.nil? || text.strip.empty?
  url?(text) && rutube_video?(text)
end

def initial_keyboard
  Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: [
    [
      Telegram::Bot::Types::InlineKeyboardButton.new(text: "Video",   callback_data: "form_vid"),
      Telegram::Bot::Types::InlineKeyboardButton.new(text: "Audio",   callback_data: "form_aud"),
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
      Telegram::Bot::Types::InlineKeyboardButton.new(text: "720p",  callback_data: "vid_720"),
      Telegram::Bot::Types::InlineKeyboardButton.new(text: "480p",  callback_data: "vid_480"),
      Telegram::Bot::Types::InlineKeyboardButton.new(text: "360p",  callback_data: "vid_360")
    ]
  ])
end
