(_final: prev: {
  claude-code = prev.claude-code.overrideAttrs (_oldAttrs: rec {
    version = "2.0.31";
    src = prev.fetchzip {
      url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
      hash = "sha256-KQRc9h2DG1bwWvMR1EnMWi9qygPF0Fsr97+TyKef3NI=";
    };
    npmDepsHash = ""; # Set to empty string to get the correct hash
  });
})
