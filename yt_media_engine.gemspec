Gem::Specification.new do |spec|
  spec.name          = "yt_media_engine"
  spec.version       = "0.1.0"
  spec.authors       = ["hizzyq, GrogSan, mambavoz"]
  spec.email         = ["you@example.com"]

  spec.summary       = "Independent engine for media downloading via yt-dlp and ffmpeg"
  spec.description   = "Ruby library that downloads audio/video by URL using yt-dlp and ffmpeg, returning file path and metadata (title, thumbnail)."
  spec.homepage      = "https://example.com/yt_media_engine"
  spec.license       = "MIT"

  spec.files         = Dir["lib/**/*", "README.md", "LICENSE", "Gemfile", "yt_media_engine.gemspec"]
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 3.0"

  spec.metadata["source_code_uri"] = spec.homepage
end

