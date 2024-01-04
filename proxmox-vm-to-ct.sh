#!/usr/bin/env bash

# License: MIT
# Author: Thushan Fernando <thushan.fernando@gmail.com>
# http://www.github.com/thushan/proxmox-vm-to-ct

VERSION=0.0.1

set -Eeuo pipefail
set -o nounset
set -o errexit
#trap cleanup EXIT

if [[ "${TRACE-0}" == "1" ]]; then
    set -o xtrace
fi

readonly ARGS="$@"
readonly ARGNUM="$#"

PVE_SOURCE=""
OPT_CLEANUP=0
OPT_DEFAULT_CONFIG=0

CT_DEFAULT_CPU=2
CT_DEFAULT_RAM=2048
CT_DEFAULT_HDD=20
CT_DEFAULT_UNPRIVILEGED=1
CT_DEFAULT_NETWORKING="name=eth0,ip=dhcp,ip6=auto,bridge=vmbr0,firewall=1"
CT_DEFAULT_FEATURES="nesting=1"

function usage() {
    echo "Usage: $0 --source <hostname> [options]"
    echo "Options:"
    echo "  --help                Display this help message"
    echo "  --source <hostname>   Source VM to convert to CT (Eg. postgres-pve.fritz.box or 192.168.0.10)"
    echo "  --cleanup             Cleanup the temporary files after conversion"
    echo "  --default-config      Default configuration for container (2 CPU, 2GB RAM, 20GB Disk)"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
    --help)
        usage
        exit 0
        ;;
    --source)
        PVE_SOURCE="$2"
        shift
        ;;
    --cleanup)
        OPT_CLEANUP=1
        ;;
    --default-config)
        OPT_DEFAULT_CONFIG=1
        ;;
    --)
        break
        ;;
    -*)
        echo "Invalid option '$1'. Use --help to see the valid options" >&2
        exit 1
        ;;
    *) ;;
    esac
    shift
done

CGrey=$(tput setaf 239)
CBlack=$(tput setaf 0)
CRed=$(tput setaf 1)
CGreen=$(tput setaf 2)
CDGreen=$(tput setaf 034)
CYellow=$(tput setaf 3)
CBlue=$(tput setaf 4)
CMagenta=$(tput setaf 5)
CCyan=$(tput setaf 6)
CWhite=$(tput setaf 7)
COrange=$(tput setaf 202)
CProxmox=$(tput setaf 166)
CDietPi=$(tput setaf 112)
BOLD=$(tput smso)
UNBOLD=$(tput rmso)
ENDMARKER=$(tput sgr0)

function banner() {
    BANNER=" ${CProxmox} ___             ${CWhite}               ${CDietPi} ___  _     _   ___ _ 
 ${CProxmox}| _ \_ _ _____ __${CWhite}_ __  _____ __ ${CDietPi}|   \(_)___| |_| _ (_)
 ${CProxmox}|  _/ '_/ _ \ \ /${CWhite} '  \/ _ \ \ / ${CDietPi}| |) | / -_)  _|  _/ |
 ${CProxmox}|_| |_| \___/_\_\\${CWhite}_|_|_\___/_\_\ ${CDietPi}|___/|_\___|\__|_| |_|

 ${CGrey}Virtual Machine${ENDMARKER} to ${CGrey}Container${ENDMARKER} Conversion Script  ${CYellow}v${VERSION}${ENDMARKER}
 ${CBlue}github.com/thushan/proxmox-vm-to-ct${ENDMARKER}
"
    printf "$BANNER"
}

function msg() {
    echo "${CMagenta}$1${ENDMARKER}"
}
function msg2() {
    echo "${CCyan}$1${ENDMARKER}"
}
function msg3() {
    echo "${CWhite}$1${ENDMARKER}"
}

function error() {
    echo "${BOLD}${CRed}ERROR:${UNBOLD}${ENDMARKER} $1${ENDMARKER}" >&2
}

function check_ok() {
    echo "[ ${CGreen}OKAY${ENDMARKER} ] $1"
}

function check_warn() {
    echo "[ ${CYellow}WARN${ENDMARKER} ] $1"
}
function check_error() {
    echo "[ ${CRed}OOPS${ENDMARKER} ] $1"
}
function check_info() {
    echo "[ ${CCyan}INFO${ENDMARKER} ] $1"
}
function fatal() {
    echo ""
    echo "${BOLD}${CRed}FATAL:${UNBOLD}${ENDMARKER} $1${ENDMARKER}" >&2
    exit 1
}

function check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        check_error "No sudo access"
        fatal "Please run as root."
    fi
    check_ok "Got sudo & we know it!"
}
function check_proxmox() {
    # Make sure we're on Proxmox
    if [ ! -f /usr/bin/pvesh ]; then
        check_error "Proxmox shell (pvesh) not found"
        fatal "Please run within Proxmox Shell"
    fi
}
function check_shell() {
    local shell=$(ps -o comm= -p $PPID)
    if [ $shell == "login" ]; then
        check_ok "Running on Proxmox host shell"
    else
        check_warn "Detected shell '${CBlue}v$shell${ENDMARKER}'. Running on Proxmox host shell is recommended"
    fi
}

function check_proxmox_version() {
    local version=$(pveversion | grep -oP '(?<=pve-manager\/)[0-9]+')
    if [ "$version" -eq 7 ] || [ "$version" -eq 8 ]; then
        check_ok "Proxmox version ${CBlue}v$version.x${ENDMARKER} is supported"
    else
        check_error "Unsupported version v$version"
        fatal "Unsupported release of Proxmox."
    fi
}
function check_pve() {
    if [ ! -x "$(command -v pveversion)" ]; then
        fatal "Script only supports Proxmox VE."
    fi
}
function check_arch() {
    local arch=$(uname -m)
    if [ $arch != "x86_64" ]; then
        fatal "This script only supports x86_64."
    else
        check_ok "Architecture ${CBlue}$arch${ENDMARKER} supported"
    fi
}

function check_args() {
    if [[ ! "$PVE_SOURCE" ]]; then
        error "Source VM not specified"
        usage
        exit 1
    fi
}
function print_opts() {
    msg "Gathering options..."
    msg3 "Source VM:   ${CBlue}$PVE_SOURCE${ENDMARKER}"
    msg3 "Cleanup:     ${CBlue}$OPT_CLEANUP${ENDMARKER}"
    msg3 "Default CT:  ${CBlue}$OPT_DEFAULT_CONFIG${ENDMARKER}"
    if [ "$OPT_DEFAULT_CONFIG" -eq 1 ]; then
        msg3 "- CPU:       ${CCyan}$CT_DEFAULT_CPU${ENDMARKER}"
        msg3 "- RAM:       ${CCyan}$CT_DEFAULT_RAM${ENDMARKER}"
        msg3 "- HDD:       ${CCyan}$CT_DEFAULT_HDD${ENDMARKER}"
        msg3 "- NETWORK:   ${CCyan}$CT_DEFAULT_NETWORKING${ENDMARKER}"
        msg3 "- FEATURES:  ${CCyan}$CT_DEFAULT_FEATURES${ENDMARKER}"
        msg3 "- UNPRIV:    ${CCyan}$CT_DEFAULT_UNPRIVILEGED${ENDMARKER}"
    fi
    msg "Gathering options...Done!"
}

main() {
    PROXMOX_NEXTID=$(pvesh get /cluster/nextid)
    TEMP_DIR=/tmp/proxmox-vm-to-ct/
    FS_OUTPUT=$TEMP_DIR/$PVE_SOURCE.tar.gz

    print_opts
    msg "Validating environment..."
    check_sudo
    check_arch
    check_shell
    check_proxmox
    check_proxmox_version
    msg "Validating environment...done!"

}

check_args

banner
check_pve
main "$@"
