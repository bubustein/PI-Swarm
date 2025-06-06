: "${LOCK_FILE:=/tmp/piswarm.lock}"

acquire_lock() {
    if [[ -e "$LOCK_FILE" ]]; then
        log ERROR "Lock file exists ($LOCK_FILE). Another instance is running or didn't exit cleanly."
        exit 1
    fi
    touch "$LOCK_FILE"
    log INFO "Lock acquired."
}
