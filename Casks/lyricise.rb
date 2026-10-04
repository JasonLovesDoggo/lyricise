cask "lyricise" do
  version "0.1.3"
  sha256 "6e148fb64e31c6dbc821061e57c20ae2d1a04d312c347489138c317cb068d5fb"

  url "https://github.com/JasonLovesDoggo/lyricise/releases/download/v#{version}/Lyricise-macos-arm64.zip"
  name "Lyricise"
  desc "Spotify lyrics in a floating window"
  homepage "https://github.com/JasonLovesDoggo/lyricise"

  depends_on arch: :arm64
  depends_on formula: "python@3.14"
  depends_on formula: "spicetify-cli"
  depends_on macos: :sequoia

  app "Lyricise.app"

  uninstall quit: "cam.jsn.lyricise"
end
