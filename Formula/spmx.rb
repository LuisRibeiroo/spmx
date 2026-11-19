class Spmx < Formula
  desc "Performant Swift Package Manager — global APFS CoW store and transparent shims for Swift & Flutter"
  homepage "https://spmx.io"
  version "0.2.4"
  url "https://get.spmx.io/releases/download/v#{version}/spmx-macos-universal.tar.gz"
  # Replace with the SHA-256 printed by `.github/workflows/release.yml` when cutting a release.
  sha256 "40f97b7adaa58e442397333993a80b07180a7eef592301587d5a016a332889f9"
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
