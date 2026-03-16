require 'net/http'
require 'json'

# Здесь, как вы понимаете, все проверки принимаемой ссылки, мб можно было не так раздувать ну да ладно

# Вариант через обращение к ютубу мне чет лень пока это настраивать
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

def valid_youtube_link?(text)
  url?(text) && youtube_video?(text)
end
