# Logging utility

GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
BLUE="\033[1;34m"
RESET="\033[0m"

log() {
    local level="$1"; shift
    local color timestamp
    case "$level" in
        INFO) color="$GREEN";;
        WARN) color="$YELLOW";;
        ERROR) color="$RED";;
        DEBUG) color="$BLUE";;
        *) color="$RESET";;
    esac
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    if [ -t 1 ]; then
        echo -e "${color}${timestamp} [${level}] $*${RESET}"
    else
        echo "${timestamp} [${level}] $*"
    fi
}
