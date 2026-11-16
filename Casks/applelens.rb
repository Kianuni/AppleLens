cask "applelens" do
  version "1.2.0"
  sha256 "0f90cb71c554d130c6a4302b92ced9d401bbfaf9fa12b9f3fe3fbf7b26905134"

  url "https://github.com/Kianuni/AppleLens/releases/download/v#{version}/AppleLens-v#{version}-universal.dmg"
  name "AppleLens"
  desc "Zero-MitM native macOS observability, USB iPhone diagnostics & PCC report suite"
  homepage "https://github.com/Kianuni/AppleLens"

  depends_on macos: ">= :sonoma"

  app "AppleLens.app"
  binary "#{appdir}/AppleLens.app/Contents/MacOS/applelens-cli", target: "applelens"

  postflight do
    system_command "/usr/bin/xattr", args: ["-cr", "#{appdir}/AppleLens.app"]
  end

  zap trash: [
    "~/Library/Preferences/com.kianuni.AppleLens.plist",
  ]
end
