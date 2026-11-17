class Spmx < Formula
  desc "Performant Swift Package Manager — global APFS CoW store and transparent shims for Swift & Flutter"
  homepage "https://spmx.io"
  version "0.1.1"
  url "https://github.com/LuisRibeiroo/spmx/releases/download/v#{version}/spmx-macos-universal.tar.gz"
  # Replace with the SHA-256 printed by `.github/workflows/release.yml` when cutting a release.
  sha256 "01d3c88d9db9d76bc8bd6c556c84cc676d319898c8e5e32e11188efa45badb4f"
  license "MIT"

  depends_on :macos

  def install
    bin.install "spmx"
  end

  def caveats
    <<~EOS
      To activate transparent shims (flutter, xcodebuild, swift), run:
        spmx setup

      Or add ~/.spmx/shims to your PATH manually after running `spmx setup --no-modify-path`:
        export PATH="$HOME/.spmx/shims:$HOME/.spmx/bin:$PATH"

      Git hooks are disabled by default. To automatically pre-warm SourcePackages
      whenever you run `git worktree add`, opt in with:
        spmx hooks enable --global
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/spmx --version")
  end
end
