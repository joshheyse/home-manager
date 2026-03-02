{
  lib,
  buildGoModule,
  fetchFromGitHub,
  libcap,
}:
buildGoModule {
  pname = "landrun";
  version = "0.1.14";

  src = fetchFromGitHub {
    owner = "Zouuup";
    repo = "landrun";
    rev = "v0.1.14";
    hash = "sha256-6TWcsJpebfLnUTYflP2j0/Tuv4PdFx/sMATc4Km1AIE=";
  };

  vendorHash = "sha256-Bs5b5w0mQj1MyT2ctJ7V38Dy60moB36+T8TFH38FA08=";

  env.CGO_ENABLED = 1;
  buildInputs = [libcap];

  subPackages = ["cmd/landrun"];

  meta = {
    description = "Run any Linux process in a Landlock sandbox";
    homepage = "https://github.com/Zouuup/landrun";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "landrun";
  };
}
