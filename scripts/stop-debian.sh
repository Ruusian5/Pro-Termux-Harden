#!/bin/bash
# --- ENTERPRISE SHUTDOWN SCRIPT (V0.3) ---
# Intelligent Stop: detect what's running before announcing, clean all stale state

DEBIANPATH="/data/local/tmp/chrootDebian"
B="/data/data/com.termux/files/usr/bin/busybox"
TERMUX_TMP="/data/data/com.termux/files/usr/tmp"
C_RED='\e[1;31m'; C_GREEN='\e[1;32m'; C_YELLOW='\e[1;33m'; C_CYAN='\e[1;36m'; NC='\e[0m'
killed_any=0

echo -e "${C_YELLOW}[~] Initiating Graceful System Cleanup...${NC}"

# ── 0. DETECT CURRENT STATE ──────────────────────────────────────────
echo -e "${C_YELLOW}[→] Scanning running services...${NC}"

X_PROC=""; pgrep -f "com.termux.x11" >/dev/null 2>&1 && X_PROC=1
pgrep -f "termux-x11" >/dev/null 2>&1 && X_PROC=1
PA_RUNNING=0; pgrep -x pulseaudio >/dev/null 2>&1 && PA_RUNNING=1
CLIP_RUNNING=0; pgrep -f clipboard-sync.sh >/dev/null 2>&1 && CLIP_RUNNING=1
CHROOT_MOUNTED=0; su -c "grep -q 'chrootDebian' /proc/mounts" 2>/dev/null && CHROOT_MOUNTED=1

echo -e "  X11:     $([ -n "$X_PROC" ] && echo "${C_GREEN}● Running${NC}" || echo "${C_RED}○ Stopped${NC}")"
echo -e "  Audio:   $([ $PA_RUNNING -eq 1 ] && echo "${C_GREEN}● Running${NC}" || echo "${C_RED}○ Stopped${NC}")"
echo -e "  Clip:    $([ $CLIP_RUNNING -eq 1 ] && echo "${C_GREEN}● Running${NC}" || echo "${C_RED}○ Stopped${NC}")"
echo -e "  Chroot:  $([ $CHROOT_MOUNTED -eq 1 ] && echo "${C_GREEN}● Mounted${NC}" || echo "${C_RED}○ Unmounted${NC}")"

# Nothing to do — short-circuit
if [ -z "$X_PROC" ] && [ $PA_RUNNING -eq 0 ] && \
   [ $CLIP_RUNNING -eq 0 ] && [ $CHROOT_MOUNTED -eq 0 ]; then
    echo -e "${C_GREEN}[✓] Nothing running — cleaning stale sockets only${NC}"
    # Still clean stale sockets
    rm -f "$TERMUX_TMP/.X0-lock" "$TERMUX_TMP/.X11-unix/X0" 2>/dev/null
    # Clean session lock inside chroot
    su -c "rm -f $DEBIANPATH/tmp/.xfce-session.lock" 2>/dev/null || true
    rm -f ~/x11_server.log*
    echo -e "${C_GREEN}[✓] Stale sockets cleaned${NC}"
    exit 0
fi

# ── 1. KILL HELPER ──────────────────────────────────────────────────
kill_proc() {
    local sig=$1 name=$2 flag=${3:--x}
    if pgrep "$flag" "$name" >/dev/null 2>&1; then
        pkill "$flag" "-$sig" "$name" 2>/dev/null || true
        killed_any=1
        echo -e "  ${C_YELLOW}[~] Killed: $name${NC}"
    fi
}

# ── 2. GRACEFUL SHUTDOWN (SIGTERM) ──────────────────────────────────
echo -e "${C_YELLOW}[→] Sending SIGTERM to running processes...${NC}"
# Chroot-side desktop processes
for proc in xfce4-session xfwm4 xfdesktop xfce4-panel xfsettingsd xfce4-notifyd; do
    su -c "pkill -15 $proc" 2>/dev/null && echo -e "  ${C_YELLOW}[~] Killed: $proc (chroot)${NC}" && killed_any=1 || true
done

# Termux-side
kill_proc 15 "termux-x11"
kill_proc 15 "pulseaudio"
kill_proc 15 "picom"
kill_proc 15 "socat"
[ $CLIP_RUNNING -eq 1 ] && pkill -f clipboard-sync.sh 2>/dev/null && echo -e "  ${C_YELLOW}[~] Killed: clipboard-sync${NC}" && killed_any=1 || true

# Kill the Termux:X11 Android activity
if [ -n "$X_PROC" ]; then
    command -v am >/dev/null 2>&1 && am force-stop com.termux.x11 2>/dev/null || true
    echo -e "  ${C_YELLOW}[~] Termux:X11 activity stopped${NC}"
fi

sleep 2

# ── 3. FORCEFUL CLEANUP (SIGKILL) ───────────────────────────────────
echo -e "${C_YELLOW}[→] Forceful cleanup of remaining processes...${NC}"
if su -c "pgrep -x xfce4-session" >/dev/null 2>&1; then su -c "pkill -9 xfce4-session" 2>/dev/null || true; fi
if su -c "pgrep -x xfwm4" >/dev/null 2>&1; then su -c "pkill -9 xfwm4" 2>/dev/null || true; fi
if su -c "pgrep -x xfdesktop" >/dev/null 2>&1; then su -c "pkill -9 xfdesktop" 2>/dev/null || true; fi
pkill -9 termux-x11 2>/dev/null || true
pkill -9 pulseaudio 2>/dev/null || true
pkill -f clipboard-sync.sh 2>/dev/null || true

# ── 3.5 KILL ALL CHROOT PROCESSES ──────────────────────────────────
# NOTE: never kill omniroute/9router — they run as ruusian and must persist.
PROTECT_RE="omniroute|9router"
echo -e "${C_YELLOW}[→] Scanning for processes inside chroot...${NC}"
CHROOT_PIDS=$(su -c "ls -l /proc/*/root 2>/dev/null" | grep "$DEBIANPATH" | awk -F'/' '{print $3}')
if [ -n "$CHROOT_PIDS" ]; then
    PIDS_TO_KILL=""
    for pid in $CHROOT_PIDS; do
        echo "$pid" | grep -qE '^[0-9]+$' || continue
        comm=$(su -c "cat /proc/$pid/comm 2>/dev/null" 2>/dev/null || true)
        if echo "$comm" | grep -qE "$PROTECT_RE"; then
            echo -e "  ${C_CYAN}[~] Preserving protected process: $comm (pid $pid)${NC}"
            continue
        fi
        PIDS_TO_KILL="$PIDS_TO_KILL $pid"
    done
    PIDS_TO_KILL=$(echo "$PIDS_TO_KILL" | tr -s ' ' | sed 's/^ //')
    if [ -n "$PIDS_TO_KILL" ]; then
        echo -e "  ${C_YELLOW}[~] Sending SIGTERM to$PIDS_TO_KILL${NC}"
        su -c "kill -15 $PIDS_TO_KILL" 2>/dev/null || true
        sleep 1.5
        CHROOT_PIDS_REM=""
        for pid in $(su -c "ls -l /proc/*/root 2>/dev/null" | grep "$DEBIANPATH" | awk -F'/' '{print $3}'); do
            echo "$pid" | grep -qE '^[0-9]+$' || continue
            comm=$(su -c "cat /proc/$pid/comm 2>/dev/null" 2>/dev/null || true)
            echo "$comm" | grep -qE "$PROTECT_RE" && continue
            CHROOT_PIDS_REM="$CHROOT_PIDS_REM $pid"
        done
        CHROOT_PIDS_REM=$(echo "$CHROOT_PIDS_REM" | tr -s ' ' | sed 's/^ //')
        if [ -n "$CHROOT_PIDS_REM" ]; then
            echo -e "  ${C_RED}[!] Force-killing remaining:$CHROOT_PIDS_REM${NC}"
            su -c "kill -9 $CHROOT_PIDS_REM" 2>/dev/null || true
        fi
        killed_any=1
        echo -e "  ${C_GREEN}[✓] Chroot processes terminated (protected ones preserved)${NC}"
    else
        echo -e "  ${C_GREEN}[✓] No killable processes inside chroot${NC}"
    fi
else
    echo -e "  ${C_GREEN}[✓] No processes inside chroot${NC}"
fi

# ── 4. CLEAN STATE ──────────────────────────────────────────────────
echo -e "${C_YELLOW}[→] Cleaning stale state...${NC}"

# X11 socket
if [ -S "$TERMUX_TMP/.X11-unix/X0" ]; then
    rm -f "$TERMUX_TMP/.X0-lock" "$TERMUX_TMP/.X11-unix/X0" 2>/dev/null
    echo -e "  ${C_YELLOW}[~] Removed stale X11 socket${NC}"
fi

# Session lock file inside chroot
su -c "rm -f $DEBIANPATH/tmp/.xfce-session.lock" 2>/dev/null || true

# Clipboard PID file
if [ -f "$TERMUX_TMP/clipboard-sync.pid" ]; then
    rm -f "$TERMUX_TMP/clipboard-sync.pid" 2>/dev/null
fi

rm -f ~/x11_server.log*

# ── 6. UNMOUNT (reverse of mount order) ──────────────────────────────
if [ $CHROOT_MOUNTED -eq 1 ]; then
    echo -e "${C_YELLOW}[→] Unmounting chroot filesystems...${NC}"
    # Isolate mount namespace so unmounts do not propagate back to host Android OS
    su -c "mount --make-rprivate $DEBIANPATH" 2>/dev/null || true
    umount_count=0
    for mp in var/lock run dev/shm tmp sdcard dev/pts sys proc dev; do
        if su -c "grep -q '$DEBIANPATH/$mp' /proc/mounts" 2>/dev/null; then
            su -c "umount -l $DEBIANPATH/$mp" 2>/dev/null && umount_count=$((umount_count+1))
        fi
    done
    echo -e "  ${C_GREEN}[✓] $umount_count mount(s) unmounted.${NC}"
else
    echo -e "  ${C_YELLOW}[~] Chroot not mounted — skipping unmount${NC}"
fi

echo ""
if [ $killed_any -eq 1 ]; then
    echo -e "${C_GREEN}[✓] All Resources Freed.${NC}"
else
    echo -e "${C_YELLOW}[~] No processes needed stopping — state cleaned.${NC}"
fi
