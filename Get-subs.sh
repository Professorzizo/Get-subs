#!/bin/bash

# ================================================
#  Get-subs.sh - Super Subdomain Enumerator (Self-Healing)
#  Author: SadiQ-Hashim
#  Repo:   github.com/SadiQ-Hashim/Get-subs
# ================================================

# Colors
GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
RESET="\033[0m"

# Spinner animation
spinner() {
    local pid=$!
    local delay=0.1
    local spin='|/-\'
    while [ -d /proc/$pid ]; do
        for i in $(seq 0 3); do
            echo -ne "\r${YELLOW}[$(echo -n $spin | cut -c $((i+1))) ] Installing...${RESET}"
            sleep $delay
        done
    done
    echo -ne "\r${GREEN}[✔] Done!${RESET}\n"
}

# ================================================
# AUTO-FIX FUNCTION
# ================================================
fix_env() {
    echo -e "${YELLOW}[+] Fixing environment & installing dependencies...${RESET}"

    # 1. Update apt repos
    sudo apt-get update --fix-missing -y || true
    sudo apt-get install -y build-essential curl wget unzip git jq || true

    # 2. Install Go if missing
    if ! command -v go &>/dev/null; then
        echo -e "${YELLOW}[+] Installing latest Go...${RESET}"
        ARCH=$(uname -m)
        if [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "arm64" ]]; then
            GO_ARCH="arm64"
        else
            GO_ARCH="amd64"
        fi

        GO_VERSION="1.22.6"
        wget -q https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz
        sudo rm -rf /usr/local/go
        sudo tar -C /usr/local -xzf go${GO_VERSION}.linux-${GO_ARCH}.tar.gz
        rm go${GO_VERSION}.linux-${GO_ARCH}.tar.gz

        echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> ~/.bashrc
        export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
    fi

    echo -e "${GREEN}[✔] Go version: $(go version)${RESET}"

    # 3. Ensure Go bin path
    mkdir -p ~/go/bin
    export PATH=$PATH:~/go/bin

    # 4. Install Go-based tools
    echo -e "${YELLOW}[+] Installing required Go tools...${RESET}"
    go install github.com/tomnomnom/assetfinder@latest
    go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
    go install github.com/projectdiscovery/httpx/cmd/httpx@latest
    go install github.com/tomnomnom/waybackurls@latest
    go install github.com/gwen001/github-subdomains@latest
}

# ================================================
# TOOL CHECKER
# ================================================
TOOLS=(assetfinder subfinder httpx jq curl waybackurls github-subdomains)

check_tools() {
    echo -e "${BLUE}[*] Checking required tools...${RESET}"
    local missing=false
    for tool in "${TOOLS[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            echo -e "${RED}[✘] $tool not found${RESET}"
            missing=true
        else
            echo -e "${GREEN}[✔] $tool found${RESET}"
        fi
    done

    if [ "$missing" = true ]; then
        echo -e "${YELLOW}[!] Missing tools detected. Auto-fixing...${RESET}"
        fix_env
    fi
}

# ================================================
# BANNER
# ================================================
clear
echo -e "${BLUE}"
echo "  ███████╗ █████╗ ██████╗ ██╗ ██████╗      ██╗  ██╗ █████╗ ███████╗██╗███╗   ███╗"
echo "  ██╔════╝██╔══██╗██╔══██╗██║██╔════╝      ██║  ██║██╔══██╗██╔════╝██║████╗ ████║"
echo "  ███████╗███████║██████╔╝██║██║  ███╗     ███████║███████║███████╗██║██╔████╔██║"
echo "  ╚════██║██╔══██║██╔═══╝ ██║██║   ██║     ██╔══██║██╔══██║╚════██║██║██║╚██╔╝██║"
echo "  ███████║██║  ██║██║     ██║╚██████╔╝     ██║  ██║██║  ██║███████║██║██║ ╚═╝ ██║"
echo "  ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝      ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝╚═╝     ╚═╝"
echo -e "${RESET}"
echo -e "            🔗 GitHub: ${YELLOW}https://github.com/SadiQ-Hashim/Get-subs${RESET}"
echo "=============================================================================="

# ================================================
# USAGE
# ================================================
if [ -z "$1" ]; then
    echo -e "${YELLOW}Usage:${RESET} $0 <target-domain>"
    echo "Example: $0 example.com"
    exit 1
fi

DOMAIN=$1
OUTPUT_DIR="recon_$DOMAIN"
SUBS_FILE="$OUTPUT_DIR/subdomain.txt"
LIVE_FILE="$OUTPUT_DIR/live-subdomain.txt"

# ================================================
# CHECK + FIX TOOLS IF NEEDED
# ================================================
check_tools

# ================================================
# START ENUMERATION
# ================================================
mkdir -p "$OUTPUT_DIR"

echo -e "\n${GREEN}[+] Collecting subdomains for $DOMAIN ...${RESET}"

# --- Assetfinder ---
echo -e "${BLUE}[+] Running assetfinder...${RESET}"
assetfinder --subs-only "$DOMAIN" | tee "$OUTPUT_DIR/assetfinder.txt"

# --- Subfinder ---
echo -e "${BLUE}[+] Running subfinder...${RESET}"
subfinder -silent -d "$DOMAIN" | tee "$OUTPUT_DIR/subfinder.txt"

# --- crt.sh scraping ---
echo -e "${BLUE}[+] Fetching from crt.sh...${RESET}"
curl -s "https://crt.sh/?q=%25.$DOMAIN&output=json" \
| jq -r '.[].name_value' | sed 's/\*\.//g' | sort -u \
| tee "$OUTPUT_DIR/crtsh.txt"

# --- Waybackurls ---
echo -e "${BLUE}[+] Gathering archived URLs from waybackurls...${RESET}"
echo "$DOMAIN" | waybackurls | awk -F/ '{print $3}' | grep "$DOMAIN" | sort -u \
| tee "$OUTPUT_DIR/waybackurls.txt"

# --- GitHub subdomains ---
echo -e "${BLUE}[+] Searching GitHub for subdomains...${RESET}"
github-subdomains -d "$DOMAIN" | tee "$OUTPUT_DIR/github.txt"

# Merge & deduplicate all
echo -e "${YELLOW}[+] Merging & sorting results...${RESET}"
cat "$OUTPUT_DIR/"*.txt | sort -u > "$SUBS_FILE"
echo -e "${GREEN}[✔] Total unique subdomains: $(wc -l < "$SUBS_FILE")${RESET}"

# --- Check which are alive ---
echo -e "${BLUE}[+] Checking live subdomains with httpx...${RESET}"
cat "$SUBS_FILE" | httpx -silent -timeout 5 -threads 50 > "$LIVE_FILE"

echo ""
echo -e "✅ ${GREEN}All subdomains saved to:${RESET}   $SUBS_FILE"
echo -e "✅ ${GREEN}Live subdomains saved to:${RESET}  $LIVE_FILE"
echo "=============================================================================="
echo -e "${YELLOW}Done! Happy Hunting - SadiQ-Hashim${RESET}"
