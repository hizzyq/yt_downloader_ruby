require_relative "lib/yt_media_engine"
# Скачивание аудио в лучшем качестве
result = YtMediaEngine::Downloader.download(
  "https://rutube.ru/shorts/fa8af564255a35eeab348c6821ef8331/",
  format: :video
)
puts result[:path]  # Путь к готовому mp3-файлу