class ScantailorAdvanced < Formula
  desc "Interactive post-processing tool for scanned pages (Advanced)"
  homepage "https://github.com/ScanTailor-Advanced/scantailor-advanced"
  url "https://github.com/ScanTailor-Advanced/scantailor-advanced/archive/refs/tags/v1.2.1.tar.gz"
  sha256 "9eb20238378151e32055f8f5c6d67cf0b4c93b77eba3f11266656879c41ac009"
  license "GPL-3.0-or-later"
  head "https://github.com/ScanTailor-Advanced/scantailor-advanced.git", branch: "master"

  depends_on "cmake" => :build
  depends_on "boost"
  depends_on "jpeg-turbo"
  depends_on "libpng"
  depends_on "libtiff"
  depends_on "qt"

  def install
    system "cmake", "-S", ".", "-B", "build",
                    "-DBUILD_TESTS=OFF",
                    *std_cmake_args
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"

    # Provide 'scantailor' symlink for convenience and compatibility
    bin.install_symlink "scantailor-advanced" => "scantailor"
  end

  test do
    assert_path_exists bin/"scantailor-advanced"
    assert_path_exists bin/"scantailor"
  end
end
