# shellcheck shell=bash
# Sets window tab formats directly, overriding the tokyo-night theme defaults.
# Uses the theme's color palette with our custom icon system.
#
# Icon resolution priority:
#   1. @pane_icon (explicit, set by pane-icon.sh)
#   2. pane_current_command auto-detection (ssh, btop, btm, htop, top)
#   3. Default terminal icon

# Tokyo Night "night" theme colors
BG="#1A1B26"
FG="#a9b1d6"
GREEN="#73daca"
BBLACK="#2A2F41"
RESET="#[fg=${FG},bg=${BG},nobold,noitalics,nounderscore,nodim]"

# Icon characters (Nerd Font)
I_SSH=$(printf '\U000f1616')
I_MON=$(printf '\U000f04c5')
I_TERM=$(printf '\ue795')

# Build icon conditional (nested tmux format conditionals).
ICON=""
ICON+="#{?#{@pane_icon},#{@pane_icon} "
ICON+=",#{?#{==:#{pane_current_command},ssh},${I_SSH} "
ICON+=",#{?#{==:#{pane_current_command},btop},${I_MON} "
ICON+=",#{?#{==:#{pane_current_command},btm},${I_MON} "
ICON+=",#{?#{==:#{pane_current_command},htop},${I_MON} "
ICON+=",#{?#{==:#{pane_current_command},top},${I_MON} "
ICON+=",${I_TERM} "
ICON+="}}}}}}"

# Current (focused) window: green icon on dark bg, bold name
tmux set -g window-status-current-format "${RESET}#[fg=${GREEN},bg=${BBLACK}] ${ICON}#[fg=${FG},bold,nodim]#W#{@claude_icon}#[nobold] "

# Unfocused window: muted icon, dim name
tmux set -g window-status-format "${RESET}#[fg=${FG}] ${ICON}${RESET}#W#{@claude_icon}#[nobold,dim] "
