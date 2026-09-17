#!/usr/bin/env zsh

afi_screen_capability() {
    emulate -L zsh
    local helper="$ARCHMIND_ROOT/tools/hardware-profile.py"
    (( $+commands[python3] )) || return 0
    [[ -f "$helper" ]] || return 0
    python3 -B "$helper" --capability "$1" >/dev/null 2>&1
}

afi_load_screen() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local screen="${1:-home}"

    typeset -ga AFI_SCREEN_ENTRIES
    typeset -g AFI_SCREEN_TITLE
    typeset -g AFI_SCREEN_BREADCRUMB
    typeset -g AFI_SCREEN_STATUS_TYPE

    AFI_SCREEN_ENTRIES=()

    case "$screen" in
        home)
            AFI_SCREEN_TITLE="Control Center"
            AFI_SCREEN_BREADCRUMB="Home"
            AFI_SCREEN_STATUS_TYPE="System"

            AFI_SCREEN_ENTRIES=(
                "System::View system information and administrative tools.::system"
                "Backup Center::Create, inspect, validate, and restore ArchMind backups.::backup"
                "Package Center::Inspect packages, updates, installation profiles, and package sources.::install"
                "System Monitor::Monitor CPU, memory, storage, temperatures, processes, and services.::monitor"
                "AI Center::Manage Ollama and locally installed AI models.::ai"
                "Python Center::Manage Python information, packages, projects, and virtual environments.::python"
                "System Settings::Configure ArchMind paths, behavior, AI model, and interface preferences.::settings"
                "Maintenance Center::Review hardware-aware maintenance, tasks, cleanup, and rollback.::maintenance"
                "ArchMind Doctor::Run system diagnostics and integrity checks.::doctor"
                "Exit::Close ArchMind and return to the terminal.::exit"
            )
            ;;

        system)
            AFI_SCREEN_TITLE="System Center"
            AFI_SCREEN_BREADCRUMB="Home / System"
            AFI_SCREEN_STATUS_TYPE="System"

            AFI_SCREEN_ENTRIES=(
                "System Information::Show the distribution, kernel, hostname, shell, desktop, and memory.::system-info"
                "Services::Show failed systemd services.::services"
                "Storage::Show root and Home space with explicit GB/GiB units.::storage"
                "System Updates::Check updates and explicitly confirm an upgrade scope.::updates"
                "Back::Return to the Control Center.::back"
            )
            ;;

        backup)
            AFI_SCREEN_TITLE="Backup Center"
            AFI_SCREEN_BREADCRUMB="Home / Backup Center"
            AFI_SCREEN_STATUS_TYPE="Backup Center"

            AFI_SCREEN_ENTRIES=(
                "Open Full Manager::Open the classic backup, restore, and installation manager.::manager-open"
                "Backup Summary::Show the backup directory, file count, and latest backup.::backup-info"
                "List Backups::List available ArchMind backup files.::backup-list"
                "Validate Latest Backup::Check the archive structure, manifest, and checksums.::verify"
                "View Backup Manifest::Display the manifest from the latest backup.::backup-manifest"
                "Create Full Backup::Create a complete ArchMind system backup.::backup-full"
                "Create Partial Backup::Choose which components should be included.::backup-partial"
                "Restore System::Open the modular restoration tools.::restore"
                "Back::Return to the Control Center.::back"
            )
            ;;

        install)
            AFI_SCREEN_TITLE="Package Center"
            AFI_SCREEN_BREADCRUMB="Home / Package Center"
            AFI_SCREEN_STATUS_TYPE="Package Center"

            AFI_SCREEN_ENTRIES=(
                "Package Summary::Show Pacman, AUR, Flatpak, and installed package statistics.::packages-summary"
                "Check Updates::Check official repositories, AUR, and Flatpak updates.::packages-updates"
                "Orphan Packages::List unused dependencies without removing them.::packages-orphans"
                "Foreign and AUR Packages::List packages outside the official repositories.::packages-foreign"
                "Installation Profiles::Show the available ArchMind installation profiles.::packages-profiles"
                "Wine Compatibility Pack::Optionally prepare one regular Wine prefix with fonts and Windows runtimes.::wine-compatibility-configure"
                "Caps Lock No Delay::Optionally remove the Caps Lock release delay with a safe keyd rule.::capslock-nodelay-configure"
                "Firefox / ChatGPT Color Emoji Fix::Fix monochrome emoji while preserving OpenAI Sans text spacing.::firefox-chatgpt-emoji-configure"
            )
            if afi_screen_capability gnome_integrations; then
                AFI_SCREEN_ENTRIES+=(
                    "Nautilus Integration::Configure folders first and real Windows executable thumbnails.::nautilus-configure"
                    "GNOME Visual Integration::Install rounded blur and yellow Papirus-Dark folders.::gnome-appearance-configure"
                    "GameMode Blur Integration::Suspend Blur My Shell automatically while games are active.::gamemode-blur-configure"
                    "GNOME Drag Hover::Optionally raise dock apps and visible windows during file drag and drop.::gnome-drag-hover-configure"
                )
            fi
            if afi_screen_capability nvidia_vibrance; then
                AFI_SCREEN_ENTRIES+=("NVIDIA Vibrance::Configure automatic Digital Vibrance after GNOME login.::nvibrant-configure")
            fi
            if afi_screen_capability plymouth_patch; then
                AFI_SCREEN_ENTRIES+=("Plymouth / Boot Visual::Audit, apply, or remove the independent Plymouth spinner patch.::plymouth-patch-configure")
            fi
            AFI_SCREEN_ENTRIES+=(
                "Open Full Manager::Open the classic ArchMind installation manager.::packages-manager"
                "Back::Return to the Control Center.::back"
            )
            ;;

        maintenance)
            AFI_SCREEN_TITLE="Maintenance Center"
            AFI_SCREEN_BREADCRUMB="Home / Maintenance Center"
            AFI_SCREEN_STATUS_TYPE="Maintenance Center"

            AFI_SCREEN_ENTRIES=(
                "Hardware Profile::Detect graphics, desktop, firmware, boot loader, and supported integrations.::maintenance-hardware"
                "Update Guardian::Scan post-update conditions and register required follow-up work.::maintenance-guardian"
                "Pending Tasks::Review maintenance work and clear completed history.::maintenance-tasks"
                "Rollback Center::Catalog safety snapshots and open registered reversible modules.::maintenance-rollback"
                "Safe Cleanup::Audit caches, journals, thumbnails, and orphan packages before any removal.::maintenance-cleanup"
                "Backup Catalog::Inspect backup origin, contents, packages, and system differences.::maintenance-backups"
                "Operating Profiles::Choose Normal, Gaming, Quiet, or Diagnostic ArchMind behavior.::maintenance-profiles"
                "Back::Return to the Control Center.::back"
            )
            ;;

        monitor)
            AFI_SCREEN_TITLE="System Monitor"
            AFI_SCREEN_BREADCRUMB="Home / System Monitor"
            AFI_SCREEN_STATUS_TYPE="System Monitor"

            AFI_SCREEN_ENTRIES=(
                "Live Monitor::Open the read-only dashboard with a one-second refresh interval.::monitor-live"
                "System Overview::Show CPU, memory, load average, uptime, storage, and failed services.::monitor-overview"
                "Processes::List the processes with the highest CPU usage.::processes"
                "Temperatures::Show available hardware temperature sensors.::temperatures"
                "Failed Services::List systemd services currently in a failed state.::monitor-services"
                "Back::Return to the Control Center.::back"
            )
            ;;

        ai)
            AFI_SCREEN_TITLE="AI Center"
            AFI_SCREEN_BREADCRUMB="Home / AI Center"
            AFI_SCREEN_STATUS_TYPE="AI Center"

            AFI_SCREEN_ENTRIES=(
                "Open Local Assistant::Start a conversation with the configured local model.::ai-chat"
                "Ollama Status::Check the executable, service, API, and default model.::ai-status"
                "Installed Models::List locally installed Ollama models.::ai-models"
                "Loaded Models::Show models currently loaded into memory.::ai-running"
                "Current Configuration::Show the default model used by ArchMind.::ai-settings"
                "Back::Return to the Control Center.::back"
            )
            ;;

        python)
            AFI_SCREEN_TITLE="Python Center"
            AFI_SCREEN_BREADCRUMB="Home / Python Center"
            AFI_SCREEN_STATUS_TYPE="Python Center"

            AFI_SCREEN_ENTRIES=(
                "Python Information::Show the executable, version, Pip, project, and active environment.::python-info"
                "Virtual Environments::Search for virtual environments in known project locations.::python-environments"
                "Installed Packages::List packages from the current Python environment.::python-packages"
                "Create .venv Environment::Create a virtual environment in the configured project.::python-venv"
                "Activation Command::Show the command used to activate the detected environment.::python-activate"
                "Current Configuration::Show the project directory used by Python Center.::python-settings"
                "Back::Return to the Control Center.::back"
            )
            ;;

        settings)
            AFI_SCREEN_TITLE="System Settings"
            AFI_SCREEN_BREADCRUMB="Home / System Settings"
            AFI_SCREEN_STATUS_TYPE="System Settings"

            AFI_SCREEN_ENTRIES=(
                "Current Settings::Show all persistent ArchMind preferences.::settings-info"
                "Default AI Model::Change the Ollama model used by ArchMind.::settings-ai-model"
                "Backup Directory::Change where ArchMind backup files are stored.::settings-backup-dir"
                "Python Project::Change the project directory used by Python Center.::settings-python-project"
                "Console Margin::Change the horizontal margin of the interface.::settings-margin"
                "Safety Confirmations::Enable or disable additional confirmation dialogs.::settings-confirmations"
                "Organize Home Zsh Files::Review loose duplicate files before moving them with a backup.::organize-home-zsh"
                "Restore Defaults::Restore all ArchMind preferences to their default values.::settings-reset"
                "Back::Return to the Control Center.::back"
            )
            ;;

        doctor)
            AFI_SCREEN_TITLE="ArchMind Doctor"
            AFI_SCREEN_BREADCRUMB="Home / ArchMind Doctor"
            AFI_SCREEN_STATUS_TYPE="ArchMind Doctor"

            AFI_SCREEN_ENTRIES=(
                "Quick Diagnosis::Run essential system health checks.::doctor-quick"
                "Full Diagnosis::Check network, packages, storage, services, audio, and system health.::doctor-full"
                "Check Pacman::Inspect the Pacman lock, local database, mirrors, and orphan packages.::doctor-pacman"
                "Check Audio::Inspect PipeWire, WirePlumber, Pulse compatibility, and audio outputs.::doctor-audio"
                "View Report::Open the latest persistent diagnostic report.::doctor-report"
                "Back::Return to the Control Center.::back"
            )
            ;;

        *)
            afi_load_screen home
            ;;
    esac
}

afi_entry_label() {
    emulate -L zsh

    local entry="${1:-}"
    print -r -- "${entry%%::*}"
}

afi_entry_description() {
    emulate -L zsh

    local entry="${1:-}"
    local remaining="${entry#*::}"

    print -r -- "${remaining%%::*}"
}

afi_entry_action() {
    emulate -L zsh

    local entry="${1:-}"
    print -r -- "${entry##*::}"
}

afi_entries_for_menu() {
    emulate -L zsh

    local entry=""

    for entry in "${AFI_SCREEN_ENTRIES[@]}"; do
        print -r -- "$(afi_entry_label "$entry")::$(afi_entry_description "$entry")"
    done
}
