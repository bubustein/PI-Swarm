release_lock() {
    rm -f "$LOCK_FILE"
    log INFO "Lock released."
}
