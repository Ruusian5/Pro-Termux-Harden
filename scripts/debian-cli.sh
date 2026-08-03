#!/bin/bash
# --- NATIVE DEBIAN CHROOT CLI MANAGEMENT TOOL ---
# Supported Architectures: ARM64 / Snapdragon 8 Gen 1/2/3/4
# Tested Root Environments: KernelSU / APatch / Magisk

DEBIANPATH="/data/local/tmp/chrootDebian"
MOUNT_SCRIPT="/data/data/com.termux/files/home/mount-debian.sh"
STOP_SCRIPT="/data/data/com.termux/files/home/stop-debian.sh"

if [ ! -f "$MOUNT_SCRIPT" ]; then
    MOUNT_SCRIPT="$(dirname "$0")/mount-debian.sh"
fi
if [ ! -f "$STOP_SCRIPT" ]; then
    STOP_SCRIPT="$(dirname "$0")/stop-debian.sh"
fi

is_mounted() {
    su -c "mountpoint -q $DEBIANPATH/proc" 2>/dev/null
    return $?
}

show_help() {
    echo "=========================================="
    echo "  Native Debian Chroot Management CLI"
    echo "=========================================="
    echo "Usage: debian-cli [command]"
    echo ""
    echo "Commands:"
    echo "  start            Start & mount Debian chroot safely"
    echo "  stop             Stop & unmount Debian chroot gracefully"
    echo "  status           Show current Debian chroot status"
    echo "  shell (or enter) Enter interactive Debian root shell (default)"
    echo "  exec <cmd>       Execute a single command inside Debian chroot"
    echo "  help             Show this help menu"
    echo ""
}

case "${1:-}" in
    start)
        echo "[*] Mounting Debian chroot environment..."
        bash "$MOUNT_SCRIPT"
        ;;
    stop)
        echo "[*] Stopping Debian chroot environment..."
        bash "$STOP_SCRIPT"
        ;;
    status)
        echo "=== Debian Chroot Status ==="
        if is_mounted; then
            echo " Status:      ACTIVE (Mounted)"
            echo " Location:    $DEBIANPATH"
        else
            echo " Status:      INACTIVE (Unmounted)"
            echo " Location:    $DEBIANPATH"
        fi
        ;;
    shell|enter|"")
        if ! is_mounted; then
            echo "[*] Initializing mounts..."
            bash "$MOUNT_SCRIPT" >/dev/null 2>&1
        fi
        exec su -c "chroot $DEBIANPATH /bin/bash -c 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin LANG=C.UTF-8 LC_ALL=C.UTF-8; exec /bin/bash --login'"
        ;;
    exec|run)
        shift
        if [ $# -eq 0 ]; then
            echo "Error: No command specified. Usage: debian-cli exec <command>"
            exit 1
        fi
        if ! is_mounted; then
            bash "$MOUNT_SCRIPT" >/dev/null 2>&1
        fi
        CMD="$*"
        exec su -c "chroot $DEBIANPATH /bin/bash -c 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin LANG=C.UTF-8 LC_ALL=C.UTF-8; $CMD'"
        ;;
    help|-h|--help)
        show_help
        ;;
    *)
        if ! is_mounted; then
            bash "$MOUNT_SCRIPT" >/dev/null 2>&1
        fi
        CMD="$*"
        exec su -c "chroot $DEBIANPATH /bin/bash -c 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin LANG=C.UTF-8 LC_ALL=C.UTF-8; $CMD'"
        ;;
esac
