#!/bin/bash
# --- PRO WORKSTATION AUTOMATED INSTALLER v0.1 ---
# Hardened Enterprise Edition
# BY RUUSIAN

set -euo pipefail

C_BOLD='\e[1m'
C_CYAN='\e[38;5;39m'
C_GREEN='\e[38;5;82m'
C_RED='\e[38;5;196m'
NC='\e[0m'

echo -e "${C_CYAN}${C_BOLD}>>> Initializing Pro Workstation Setup v0.1 by Ruusian...${NC}"

# 1. Root Verification
if [[ $(id -u) -ne 0 ]] && ! command -v su > /dev/null; then
    echo -e "${C_RED}[!] Error: This setup requires SuperUser (Root) access.${NC}"
    exit 1
fi

# 2. Termux Dependency Injection
echo -e "\n${C_BOLD}[1/5] Injecting Termux Dependencies...${NC}"
pkg update -y || echo -e "${C_RED}[!] Package update failed. Check internet connection.${NC}"

# List of critical host dependencies
PACKAGES=(
    "git" "busybox" "xclip" "pulseaudio" "mesa" 
    "virglrenderer-android" "termux-x11-nightly" 
    "bc" "socat" "xorg-xhost" "ncurses-utils" "termux-api"
)

for pkg in "${PACKAGES[@]}"; do
    echo -ne "  [~] Installing $pkg... "
    if pkg install -y "$pkg" >/dev/null 2>&1; then
        echo -e "${C_GREEN}OK${NC}"
    else
        echo -e "${C_RED}FAILED${NC}"
    fi
done

# 3. Environment Synchronization
echo -e "\n${C_BOLD}[2/5] Deploying System Management Scripts...${NC}"
REPO_DIR=$(pwd)
# Ensure we are in the right directory
if [ ! -d "scripts" ]; then
    echo -e "${C_RED}[!] Error: scripts directory not found. Are you in the repo root?${NC}"
    exit 1
fi

cp -v scripts/*.sh "$HOME/"
chmod +x "$HOME"/*.sh

# 4. Shell Integration
echo -e "\n${C_BOLD}[3/5] Configuring Shell (.bashrc)...${NC}"
if ! grep -q "cmds.sh" "$HOME/.bashrc" 2>/dev/null; then
    cat << 'EOF' >> "$HOME/.bashrc"

# --- PRO WORKSTATION HUD ---
alias agy='bash ~/cmds.sh'
alias res='bash ~/res.sh'
alias sd='bash ~/stop-debian.sh'
alias fix='bash ~/repair.sh'
alias gpu='bash ~/gpu-check.sh'
alias debian='bash ~/debian-cli.sh shell'
alias debian-start='bash ~/debian-cli.sh start'
alias debian-stop='bash ~/debian-cli.sh stop'
alias debian-status='bash ~/debian-cli.sh status'

if [[ $- == *i* ]]; then
    termux-wake-lock 2>/dev/null
fi
EOF
    echo -e "  [✓] Aliases and banner added to .bashrc"
else
    echo -e "  [~] .bashrc already configured."
fi

# 5. Chroot Hardening & Fixes
echo -e "\n${C_BOLD}[4/5] Synchronizing Debian Guest Environment...${NC}"
DEBIANPATH="/data/local/tmp/chrootDebian"

if ! su -c "test -d $DEBIANPATH" 2>/dev/null; then
    echo -e "${C_RED}[!] Warning: Debian chroot not found at $DEBIANPATH${NC}"
    echo -e "Please ensure your Debian chroot is extracted to that location."
else
    # Trigger mount bridge
    bash "$HOME/mount-debian.sh"
    
    # Sync internal configs
    # We use a temporary script for the complex su -c block to avoid quoting issues
    SYNC_SCRIPT=$(mktemp)
    cat << EOF > "$SYNC_SCRIPT"
#!/bin/sh
set -eu
mkdir -p "$DEBIANPATH/etc/profile.d/" "$DEBIANPATH/usr/local/bin/" "$DEBIANPATH/home/ruusian/" "$DEBIANPATH/etc/sudoers.d/" "$DEBIANPATH/run/"
cp -v "$REPO_DIR/configs/debian/etc/profile.d/"*.sh "$DEBIANPATH/etc/profile.d/"
cp -v "$REPO_DIR/configs/debian/usr/local/bin/"*.sh "$DEBIANPATH/usr/local/bin/"
cp -v "$REPO_DIR/configs/debian/home/ruusian/fix_mmap.c" "$DEBIANPATH/home/ruusian/"
chmod +x "$DEBIANPATH/usr/local/bin/"*.sh

# Setup chroot networking (bind host resolv)
cp /data/data/com.termux/files/usr/etc/resolv.conf "$DEBIANPATH/etc/resolv.conf" 2>/dev/null || echo "nameserver 8.8.8.8" > "$DEBIANPATH/etc/resolv.conf"
chmod 644 "$DEBIANPATH/etc/resolv.conf"

# Guest Environment Preparation
echo -e "\n${C_BOLD}[5/6] Hardening Guest User & Packages...${NC}"
chroot "$DEBIANPATH" /bin/sh -c '
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    export DEBIAN_FRONTEND=noninteractive

    # Create User
    groupadd -g 1000 ruusian || true
    useradd -u 1000 -g 1000 -d /home/ruusian -s /bin/bash ruusian || true
    chown -R 1000:1000 /home/ruusian

    # Fix APT (Disable broken nodesource if present)
    [ -f /etc/apt/sources.list.d/nodesource.sources ] && mv /etc/apt/sources.list.d/nodesource.sources /etc/apt/sources.list.d/nodesource.sources.bak

    # Install Workstation Essentials
    apt update
    apt install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
        gcc libc6-dev xfce4 xfce4-terminal dbus-x11 picom python3 locales sudo openssh-client socat

    # Set Passwords
    echo "root:1234" | chpasswd
    echo "ruusian:1234" | chpasswd

    # Configure Sudo
    usermod -aG sudo ruusian
    echo "ruusian ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/ruusian-workstation
    chmod 440 /etc/sudoers.d/ruusian-workstation
'

# Building Kernel Bypass Library
echo -e "\n${C_BOLD}[6/6] Building Kernel Bypass Library...${NC}"
chroot "$DEBIANPATH" /bin/sh -c '
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    gcc -shared -fPIC -ldl /home/ruusian/fix_mmap.c -o /home/ruusian/fix_mmap.so
    echo "/home/ruusian/fix_mmap.so" > /etc/ld.so.preload
'
EOF
    su -c "sh $SYNC_SCRIPT"
    rm -f "$SYNC_SCRIPT"
fi

echo -e "\n${C_GREEN}${C_BOLD}>>> SETUP COMPLETE! <<<${NC}"
echo -e "Please restart Termux and type ${C_CYAN}'agy'${NC} to launch your dashboard."
