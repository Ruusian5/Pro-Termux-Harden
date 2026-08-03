#!/bin/bash
# --- NATIVE DEBIAN CHROOT MOUNT BRIDGE ---
# Mounts essential filesystems with rslave/rprivate namespace isolation
# to prevent mount propagation or crashes on host Android OS.

DEBIANPATH="/data/local/tmp/chrootDebian"
TERMUX_TMP="/data/data/com.termux/files/usr/tmp"

echo -e "\e[1;33m[~] Synchronizing Hardware Bridges...\e[0m"

su -c "
    # Self-bind DEBIANPATH so it becomes a dedicated mountpoint, then make it rprivate.
    # Passing both arguments (\$DEBIANPATH \$DEBIANPATH) is REQUIRED for Android toybox mount
    # so it does not fallback to reading missing /etc/fstab and changing host /data propagation.
    if ! grep -q -w \"$DEBIANPATH\" /proc/mounts 2>/dev/null; then
        mount -o bind \"$DEBIANPATH\" \"$DEBIANPATH\" 2>/dev/null || true
    fi
    mount -o rprivate \"$DEBIANPATH\" \"$DEBIANPATH\" 2>/dev/null || true

    # Helper function for idempotent bind mounts with rslave isolation
    domount() {
        if ! grep -q -w \"\$2\" /proc/mounts; then
            mount -o bind \"\$1\" \"\$2\" 2>/dev/null && mount -o rslave \"\$2\" \"\$2\" 2>/dev/null || true
        fi
    }

    # Helper function for idempotent tmpfs mounts
    dotmpfs() {
        if ! grep -q -w \"\$2\" /proc/mounts; then
            mount -t tmpfs tmpfs \"\$2\" -o \"\$3\"
        fi
    }

    # Ensure internal directories exist
    mkdir -p $DEBIANPATH/dev $DEBIANPATH/proc $DEBIANPATH/sys $DEBIANPATH/sdcard $DEBIANPATH/tmp $DEBIANPATH/run
    # /var/lock is a symlink to /run/lock inside the chroot — replace with a real
    # dir so tmpfs can mount on it (mount doesn't follow symlinks).
    # Skip if already mounted (e.g. from a previous mount-debian run).
    if ! grep -q -w "$DEBIANPATH/var/lock" /proc/mounts 2>/dev/null; then
        rm -rf $DEBIANPATH/var/lock
        mkdir -p $DEBIANPATH/var/lock
    fi
    # Don't create dev/shm here — /dev bind-mount below would hide it
    mkdir -p $DEBIANPATH/dev/pts

    domount /dev $DEBIANPATH/dev
    domount /proc $DEBIANPATH/proc
    domount /sys $DEBIANPATH/sys
    domount /dev/pts $DEBIANPATH/dev/pts
    domount /sdcard $DEBIANPATH/sdcard

    # /tmp needs special handling: Android's F2FS creates a phantom mount
    # at the chroot path that tricks domount into skipping the real bind.
    # Check for the actual bind from usr/tmp; if missing, unmount and re-bind.
    if grep -q "usr/tmp $DEBIANPATH/tmp " /proc/mounts 2>/dev/null; then
        : # correct bind mount already in place
    else
        umount "$DEBIANPATH/tmp" 2>/dev/null || umount -l "$DEBIANPATH/tmp" 2>/dev/null || true
        mount --bind "$TERMUX_TMP" "$DEBIANPATH/tmp"
    fi

    # X11 socket is shared through the Termux tmp bind mount above
    mkdir -p $TERMUX_TMP/.X11-unix $DEBIANPATH/tmp/.X11-unix 2>/dev/null || true

    # Mount tmpfs components (dev/shm AFTER /dev bind mount so target exists)
    mkdir -p $DEBIANPATH/dev/shm 2>/dev/null || true
    dotmpfs tmpfs $DEBIANPATH/dev/shm rw,nosuid,nodev,noatime
    dotmpfs tmpfs $DEBIANPATH/run rw,mode=1777,noatime
    dotmpfs tmpfs $DEBIANPATH/var/lock rw,mode=1777,noatime

    # Permissions
    # \$RUUSIAN_UID is escaped so the parent shell doesn't expand it —
    # it's defined INSIDE the su block and must not be pre-expanded.
    RUUSIAN_UID=\$(chroot $DEBIANPATH /usr/bin/id -u ruusian 2>/dev/null || echo 1000)
    mkdir -p $DEBIANPATH/run/user/\$RUUSIAN_UID
    chown \$RUUSIAN_UID:\$RUUSIAN_UID $DEBIANPATH/run/user/\$RUUSIAN_UID
    chmod 777 $DEBIANPATH/run/user/\$RUUSIAN_UID
    chmod 660 /dev/kgsl-3d0 /dev/dri/* /dev/video* /dev/ion /dev/adsp* /dev/adsprpc* 2>/dev/null || true
"

echo -e "\e[1;32m[✓] All Bridges Verified and Mounted.\e[0m"
