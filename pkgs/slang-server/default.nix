{
  boost,
  cmake,
  fetchgit,
  fmt,
  lib,
  ninja,
  python3,
  stdenv,
  tomlplusplus,
}:
stdenv.mkDerivation {
  pname = "slang-server";
  version = "0.2.9";

  src = fetchgit {
    url = "https://github.com/hudson-trading/slang-server.git";
    rev = "4f33c99d8d41f254450e7396260861d55e6243b6";
    fetchSubmodules = true;
    hash = "sha256-6Lc9rS8FEUSYcr2ulRqez7Of3awsxw3T6DsvZr9sVWI=";
  };

  nativeBuildInputs = [
    cmake
    ninja
    python3
  ];

  buildInputs = [
    boost
    fmt
    tomlplusplus
  ];

  postPatch = ''
    substituteInPlace CMakeLists.txt \
      --replace-fail "set(CMAKE_DISABLE_FIND_PACKAGE_fmt TRUE)" ""
    substituteInPlace CMakeLists.txt \
      --replace-fail "include(FetchContent)" "find_package(fmt 12.1 REQUIRED)"$'\n'"include(FetchContent)"
    substituteInPlace external/slang/external/CMakeLists.txt \
      --replace-fail "find_package(fmt 12.2 REQUIRED)" "find_package(fmt 12.1 REQUIRED)"
  '';

  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DSLANG_SERVER_INCLUDE_TESTS=OFF"
    "-DSLANG_SERVER_INCLUDE_INSTALL=ON"
    "-DSLANG_USE_CPPTRACE=OFF"
    "-DSLANG_USE_MIMALLOC=OFF"
    "-DSLANG_USE_SYSTEM_BOOST=ON"
    "-DSLANG_USE_SYSTEM_FMT=ON"
  ];

  meta = {
    description = "SystemVerilog language server based on the Slang frontend";
    homepage = "https://github.com/hudson-trading/slang-server";
    license = lib.licenses.mit;
    mainProgram = "slang-server";
    platforms = lib.platforms.unix;
  };
}
