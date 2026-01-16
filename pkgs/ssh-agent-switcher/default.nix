{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule {
  pname = "ssh-agent-switcher";
  version = "unstable-2025-10-02"; # Update as needed

  src = fetchFromGitHub {
    owner = "jmmv";
    repo = "ssh-agent-switcher";
    rev = "main";
    sha256 = "sha256-QsWngp0z7yNOamItmlLJp1K+drdXuAtuIQXcSDkDiQs=";
  };

  vendorHash = null;

  doCheck = false;

  meta = {
    description = "A highly configurable, multi-protocol DNS forwarding proxy";
    homepage = "https://github.com/jmmv/ssh-agent-switcher.git";
    license = lib.licenses.bsd3;
    mainProgram = "ssh-agent-switcher";
  };
}
