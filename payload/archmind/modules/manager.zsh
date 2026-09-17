# ==========================================
# ArchMind Manager integration
# Backup, restoration, and installation
# ==========================================

archmind_manager() {
    local manager="${ARCHMIND_HOME}/bin/archmind-manager"

    if [[ ! -x "$manager" ]]; then
        _archmind_error "ArchMind Manager not found or not executable: $manager"
        return 1
    fi

    "$manager"
}

ambackup() {
    archmind_manager
}
