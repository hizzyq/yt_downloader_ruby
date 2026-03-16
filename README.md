# YtMediaEngine

Independent Ruby engine for downloading media with `yt-dlp` and `ffmpeg`.

## Installation

Add this line to your application's Gemfile:

```ruby
gem "yt_media_engine", path: "./yt_media_engine"
```

And then execute:

```bash
bundle install
```

You must have `yt-dlp` and `ffmpeg` installed and available in `PATH`, or provide explicit paths in options.

## Usage

```ruby
require "yt_media_engine"

result = YtMediaEngine::Downloader.download(
  "https://www.youtube.com/watch?v=XXXX",
  format: :audio,          # or :video
  audio_format: "mp3",     # for audio
  quality: "bestaudio/best"
)

puts result[:path]           # absolute path to ready file
puts result[:title]          # video title
puts result[:thumbnail_url]  # original thumbnail URL
puts result[:thumbnail_path] # local thumbnail path (if downloaded)
```

### Custom paths

```ruby
result = YtMediaEngine::Downloader.download(
  url,
  output_dir: "storage/media",
  yt_dlp_path: "C:/tools/yt-dlp.exe",
  ffmpeg_path: "C:/tools/ffmpeg.exe"
)
```

## License

MIT

