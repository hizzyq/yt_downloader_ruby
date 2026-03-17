require_relative "lib/yt_media_engine"
# Скачивание аудио в лучшем качестве
result = YtMediaEngine::Downloader.download(
  "https://rutube.ru/shorts/291ade6f19d23f15a59cbf9ff719479b/",
  format: :audio
)
puts result[:path]  # Путь к готовому mp3-файлу