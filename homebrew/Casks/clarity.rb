cask "clarity" do
  # Update version + sha256 on every release (see docs/release.md).
  # sha256 must match dist/Clarity-<version>-macos.zip from the GitHub Release.
  version "1.0.0"
  sha256 "574f8277c2db38c227a377728ec58843231474a9e9c0ec9834be5cc587499067"

  url "https://github.com/hariprasad2512/clarity_flutter/releases/download/v#{version}/Clarity-#{version}-macos.zip"
  name "Clarity"
  desc "Minimal local-first todo app"
  homepage "https://github.com/hariprasad2512/clarity_flutter"

  # Unsigned build (no paid Apple Developer ID): users must install with
  #   brew install --cask --no-quarantine clarity
  # and on first launch may need right-click → Open.
  app "Clarity.app"

  zap trash: [
    "~/Library/Application Support/clarity_flutter",
    "~/Library/Preferences/com.harry.Clarity.plist",
  ]
end
