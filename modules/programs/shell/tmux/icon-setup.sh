# shellcheck shell=bash
# Replaces tokyo-night-tmux's SSH-only icon conditional with an expanded
# version supporting multiple window types.
#
# Icon resolution priority:
#   1. @pane_icon (explicit, set by pane-icon.sh)
#   2. pane_current_command auto-detection (ssh, btop, btm, htop, top)
#   3. Default terminal icon

# Icon characters (Nerd Font)
I_SSH=$(printf '\U000f1616')
I_MON=$(printf '\U000f04c5')
I_TERM=$(printf '\ue795')

# Build expanded icon conditional (nested tmux format conditionals).
# Each branch: "icon " (icon + trailing space to match theme spacing).
ICON_COND=""
ICON_COND+="#{?#{@pane_icon},#{@pane_icon} "
ICON_COND+=",#{?#{==:#{pane_current_command},ssh},${I_SSH} "
ICON_COND+=",#{?#{==:#{pane_current_command},btop},${I_MON} "
ICON_COND+=",#{?#{==:#{pane_current_command},btm},${I_MON} "
ICON_COND+=",#{?#{==:#{pane_current_command},htop},${I_MON} "
ICON_COND+=",#{?#{==:#{pane_current_command},top},${I_MON} "
ICON_COND+=",${I_TERM} "
ICON_COND+="}}}}}}"

for fmt_opt in window-status-format window-status-current-format; do
  current=$(tmux show -gv "$fmt_opt" 2>/dev/null) || continue

  # Only modify if the theme's SSH conditional is present
  if [[ "$current" != *"#{pane_current_command},ssh}"* ]]; then
    continue
  fi

  # Use awk to find and replace the SSH conditional by matching braces.
  # The theme's pattern: #{?#{==:#{pane_current_command},ssh},ICON,ICON}
  updated=$(printf '%s' "$current" | awk -v icon_fmt="$ICON_COND" '
  BEGIN { marker = "#{?#{==:#{pane_current_command},ssh}," }
  {
    idx = index($0, marker)
    if (idx > 0) {
      prefix = substr($0, 1, idx - 1)
      rest = substr($0, idx)
      depth = 0
      end_pos = 0
      n = length(rest)
      for (i = 1; i <= n; i++) {
        c = substr(rest, i, 1)
        if (c == "{") depth++
        if (c == "}") {
          depth--
          if (depth == 0) {
            end_pos = i
            break
          }
        }
      }
      if (end_pos > 0) {
        suffix = substr(rest, end_pos + 1)
        printf "%s%s%s", prefix, icon_fmt, suffix
      } else {
        printf "%s", $0
      }
    } else {
      printf "%s", $0
    }
  }')

  tmux set -g "$fmt_opt" "$updated"
done
