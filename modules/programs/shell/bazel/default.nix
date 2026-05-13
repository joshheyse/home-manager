{
  pkgs,
  lib,
  ...
}: let
  refreshScript = pkgs.writeShellApplication {
    name = "bazel-refresh-targets";
    runtimeInputs = with pkgs; [
      bazelisk
      coreutils
      findutils
      gnused
    ];
    # The script is written to be sh-compatible enough; writeShellApplication
    # runs it with `bash` and applies shellcheck at build time.
    text = builtins.readFile ./refresh-targets.sh;
    # Allow the non-literal `(cd ... && ...) >"$tmp"` and the background
    # subshell pattern; shellcheck otherwise flags nothing here but keep the
    # option available if future edits need it.
    excludeShellChecks = [];
  };
in {
  home.packages = [refreshScript];

  # Install the completion function onto a directory that zsh's compinit
  # will load. The zsh module adds $HOME/.config/zsh/completions to fpath.
  home.file.".config/zsh/completions/_bazelisk".source = ./_bazelisk;

  programs.zsh.initContent = lib.mkAfter ''
    # Bazel/bazelisk completion: wire up symlink so `bazel` shares the function.
    if (( $+functions[_bazelisk] )) || [[ -r "$HOME/.config/zsh/completions/_bazelisk" ]]; then
      compdef _bazelisk bazelisk bazel
    fi
  '';
}
