class Cangjie < Formula
  desc "Ecosystem for the Cangjie compiler"
  homepage "https://cangjie-lang.cn/en"
  url "https://gitcode.com/Cangjie/cangjie_compiler.git",
    revision: "dc1f7a85715ffaa0142b250a8f0c1b4e5f0dab52",
    tag:      "v1.0.5"
  license "Apache-2.0"

  depends_on "cmake" => :build
  depends_on "llvm@16" => :build
  depends_on "ninja" => :build
  depends_on "python@3.14" => :build
  depends_on "gnu-tar"
  depends_on "googletest"
  depends_on :macos
  depends_on "openssl@3"

  uses_from_macos "bison"
  uses_from_macos "m4"

  # Additional dependency
  resource "cangjie_runtime" do
    url "https://gitcode.com/Cangjie/cangjie_runtime.git",
      revision: "7cfb8a627ccbc5a7dacee022ada06d074375aaf2",
      tag:      "v1.0.5"
  end
  resource "cangjie_stdx" do
    url "https://gitcode.com/Cangjie/cangjie_stdx.git",
      revision: "69976a1c5ee1f720a6457a0310d9eb7c5a96eba8",
      tag:      "v1.0.5.1"
  end

  def install
    arch = Hardware::CPU.arm? ? "aarch64" : "x86_64"
    sdk_name = Hardware::CPU.arm? ? "mac-aarch64" : "mac-x64"
    cangjie_version="1.5.0"
    stdx_version="1.5.0.1"
    ENV["ARCH"] = arch
    ENV["SDK_NAME"] = sdk_name
    ENV["CANGJIE_VERSION"] = cangjie_version
    ENV["STDX_VERSION"] = stdx_version

    ENV.prepend_path "PATH", Formula["llvm@16"].opt_bin
    ENV.prepend_path "PATH", Formula["m4"].opt_bin
    openssl_path=Formula["openssl@3"].opt_lib
    ENV["OPENSSL_PATH"] = openssl_path
    ENV.prepend_path "LD_LIBRARY_PATH", openssl_path

    # move all the files from the cangjie_compiler repository into cangjie_compiler folder
    mkdir_p buildpath/"cangjie_compiler"
    buildpath.children.each do |child|
      next if child == buildpath/"cangjie_compiler"

      mv child, buildpath/"cangjie_compiler"
    end

    resource("cangjie_runtime").stage buildpath/"cangjie_runtime"
    resource("cangjie_stdx").stage buildpath/"cangjie_stdx"

    # --- compiler ---
    Dir.chdir("#{buildpath}/cangjie_compiler") do
      # apply patch -- this should be temporary
      system "git", "remote", "add", "compiler_fix", "https://gitcode.com/claudio_/cangjie_compiler.git"
      system "git", "fetch", "compiler_fix"
      system "git", "cherry-pick", "092bef1a02f066ff2786d12f04a16063b30cca3d"
      system "git", "cherry-pick", "890edb3ba3df893d879549c3d82ea9d9d620416b"

      system "python3", "build.py", "clean"
      # TODO: build with --build-cjdb
      # system "python3", "build.py", "build", "-t", "release", "--no-tests", "--build-cjdb"
      system "python3", "build.py", "build", "-t", "release", "--no-tests"
      system "python3", "build.py", "install"
    end

    # --- runtime ---
    Dir.chdir("#{buildpath}/cangjie_runtime/runtime") do
      # apply patch -- this should be temporary
      system "git", "remote", "add", "runtime_fix", "https://gitcode.com/magnusmorton/cangjie_runtime.git"
      system "git", "fetch", "runtime_fix"
      system "git", "cherry-pick", "6fdd41f22576345e45c4c7b507d55593d556ed81"
      system "git", "remote", "add", "runtime_fix_2", "https://gitcode.com/claudio_/cangjie_runtime.git"
      system "git", "fetch", "runtime_fix_2"
      system "git", "cherry-pick", "754b3aa9575626a56b46a400dd7c013430028895"
      system "git", "cherry-pick", "ff82ed169b4d109ac83c3af960270b484ed8aa1f"

      system "python3", "build.py", "clean"
      system "python3", "build.py", "build", "-t", "release", "-v", cangjie_version
      system "python3", "build.py", "install"
      cp_r "#{buildpath}/cangjie_runtime/runtime/output/common/darwin_release_#{arch}/lib",
          "#{buildpath}/cangjie_compiler/output"
      cp_r "#{buildpath}/cangjie_runtime/runtime/output/common/darwin_release_#{arch}/runtime",
          "#{buildpath}/cangjie_compiler/output"
    end

    # homebrew will ned to replace @rpath
    ENV.append "LDFLAGS", " "

    # --- std ---
    Dir.chdir("#{buildpath}/cangjie_runtime/stdlib") do
      system "python3", "build.py", "clean"
      system "bash", "-c", <<~EOS
        source #{buildpath}/cangjie_compiler/output/envsetup.sh
        python3 build.py build -t release --target-lib=#{buildpath}/cangjie_runtime/runtime/output --target-lib=#{openssl_path}
      EOS
      system "python3", "build.py", "install"
      cp_r Dir.glob("#{buildpath}/cangjie_runtime/stdlib/output/*"), "#{buildpath}/cangjie_compiler/output/"
    end

    # --- stdx ---
    Dir.chdir("#{buildpath}/cangjie_stdx") do
      system "git", "remote", "add", "stdx_fix", "https://gitcode.com/claudio_/cangjie_stdx.git"
      system "git", "fetch", "stdx_fix"
      system "git", "cherry-pick", "22fc2a1a59c51a60597aa25a42a78ccf25e3da6a"

      system "python3", "build.py", "clean"
      system "bash", "-c", <<~EOS
        source #{buildpath}/cangjie_compiler/output/envsetup.sh
        python3 build.py build -t release --include=#{buildpath}/cangjie_compiler/include --target-lib=#{openssl_path}
      EOS
      system "python3", "build.py", "install"
    end

    # Add CANGJIE_STDX_PATH to the envsetup.h so that stdx is also visible to the user
    File.open("#{buildpath}/cangjie_compiler/output/envsetup.sh", "a") do |f|
      f.puts "export CANGJIE_STDX_PATH=${CANGJIE_HOME}/cangjie_stdx/static/stdx"
    end

    prefix.install "#{buildpath}/cangjie_compiler/output"
    (prefix/"output"/"cangjie_stdx").install Dir["#{buildpath}/cangjie_stdx/target/darwin_#{arch}_cjnative/*"]
  end

  def caveats
    <<~EOS
      To use Cangjie, you need to set up your environment:

        source #{prefix}/output/envsetup.sh

      You can add this to your ~/.bashrc or ~/.zshrc.
    EOS
  end

  test do
    File.open("test.cj", "w") do |f|
      f.puts 'main() {println("Hello world!")}'
    end
    assert_match "Hello world!", shell_output("source #{prefix}/output/envsetup.sh && cjc test.cj && ./main")
  end
end
