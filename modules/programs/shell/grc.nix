{
  pkgs,
  lib,
  ...
}: {
  home.packages = [pkgs.grc];

  # grc's shipped zsh integration aliases ls, ps, df, ip, docker, etc. with
  # `grc -es --colour=auto`. The script self-guards on $TERM and grc presence.
  programs.zsh.initContent = lib.mkAfter ''
    if [[ -r "${pkgs.grc}/etc/grc.zsh" ]]; then
      source "${pkgs.grc}/etc/grc.zsh"
    fi
  '';
}
