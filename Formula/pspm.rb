class Pspm < Formula
  desc "Performant Swift Package Manager — global APFS CoW store and transparent shims for Swift & Flutter"
  homepage "https://github.com/LuisRibeiroo/pspm"
  version "0.1.0"
  url "https://github.com/LuisRibeiroo/pspm/releases/download/v#{version}/pspm-macos-universal.tar.gz"
  # Replace with the SHA-256 printed by `.github/workflows/release.yml` when cutting a release.
  sha256 "REPLACE_WITH_RELEASE_TARBALL_SHA256"
  license "MIT"

  depends_on :macos

  def install
    bin.install "pspm"
  end

  def caveats
    <<~EOS
      To activate transparent shims (flutter, xcodebuild, swift), run:
        pspm setup

      Or add ~/.pspm/shims to your PATH manually after running `pspm setup --no-modify-path`:
        export PATH="$HOME/.pspm/shims:$HOME/.pspm/bin:$PATH"

      Git hooks are disabled by default. To automatically pre-warm SourcePackages
      whenever you run `git worktree add`, opt in with:
        pspm hooks enable --global
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/pspm --version")
  end
end
