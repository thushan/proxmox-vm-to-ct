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
PVE_TARGET=""
PVE_STORAGE=""
PVE_DESCRIPTION="Converted from VM to CT via <a href="http://www.github.com/thushan/proxmox-vm-to-ct">proxmox-vm-to-ct</a>."

OPT_CLEANUP=0
OPT_DEFAULT_CONFIG=0
OPT_SOURCE_OUTPUT=""

CT_DEFAULT_CPU=2
CT_DEFAULT_RAM=2048
CT_DEFAULT_HDD=20
CT_DEFAULT_UNPRIVILEGED=1
CT_DEFAULT_NETWORKING="name=eth0,ip=dhcp,ip6=auto,bridge=vmbr0,firewall=1"
CT_DEFAULT_FEATURES="nesting=1"
CT_DEFAULT_ONBOOT=0
CT_DEFAULT_ARCH="amd64"
CT_DEFAULT_OSTYPE="debian"

function usage() {
    echo "Usage: $0 --storage <name> --target <name> --source <hostname> [options]"
    echo "Options:"
    echo "  --storage <name>"
    echo "      Name of the Proxmox Storage container (Eg. local-zfs, local-lvm, etc)"
    echo "  --target <name>"
    echo "      Name of the container to create (Eg. postgres-ct)"
    echo "  --source <hostname>"
    echo "      Source VM to convert to CT (Eg. postgres-vm.fritz.box or 192.168.0.10)"
    echo "  --source-output <path>, --output <path>, -o <path>"
    echo "      Location of the source VM output (default: /tmp/proxmox-vm-to-ct/<hostname>.tar.gz)"
    echo "  --cleanup"
    echo "      Cleanup the source compressed image after conversion (the *.tar.gz file)"
    echo "  --default-config"
    echo "      Default configuration for container (2 CPU, 2GB RAM, 20GB Disk)"
    echo "  --help"
    echo "      Display this help message"
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
    --storage)
        PVE_STORAGE="$2"
        shift
        ;;
    --target)
        PVE_TARGET="$2"
        shift
        ;;
    -o|--output|--source-output)
        OPT_SOURCE_OUTPUT="$2"
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
 ${CProxmox}| | |_| \___/_\_\\${CWhite}_|_|_\___/_\_\ ${CDietPi}|___/|_\___|\__|_| |_| 
 ${CProxmox}|_|${CBlue}github.com/thushan/proxmox-vm-to-ct${ENDMARKER}          ${CYellow}v${VERSION}${ENDMARKER}

   Your ${CGrey}Virtual Machine${ENDMARKER} to ${CGrey}Container${ENDMARKER} Conversion Script

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
    if [[ "$EUID" -ne 0 ]]; then
        check_error "No sudo access"
        fatal "Please run as root."
    fi
    check_ok "Got sudo & we know it!"
}
function check_proxmox() {
    # Make sure we're on Proxmox
    if [[ ! -f /usr/bin/pvesh ]]; then
        check_error "Proxmox shell (pvesh) not found"
        fatal "Please run within Proxmox Shell"
    fi
}
function check_shell() {
    local shell=$(ps -o comm= -p $PPID)
    if [[ $shell == "login" ]]; then
        check_ok "Running on Proxmox host shell"
    else
        check_warn "Detected shell '${CBlue}v$shell${ENDMARKER}'. Running on Proxmox host shell is recommended"
    fi
}

function check_proxmox_storage() {
    if [[ ${PVE_STORAGE_LIST[@]} =~ $PVE_STORAGE ]]; then
        check_ok "Storage ${CBlue}$PVE_STORAGE${ENDMARKER} found"
    else
        IFS=,
        check_error "Storage ${CBlue}$PVE_STORAGE${ENDMARKER} not found (detected: ${CBlue}$(IFS=,; echo "${PVE_STORAGE_LIST[*]}")${ENDMARKER})"
        fatal "Please specify a valid storage name"
    fi
}

function check_proxmox_version() {
    local version=$(pveversion | grep -oP '(?<=pve-manager\/)[0-9]+')
    if [[ "$version" -eq 7 ]] || [[ "$version" -eq 8 ]]; then
        check_ok "Proxmox version ${CBlue}v$version.x${ENDMARKER} is supported"
    else
        check_error "Unsupported version v$version"
        fatal "Unsupported release of Proxmox."
    fi
}
function check_pve() {
    if [[ ! -x "$(command -v pveversion)" ]]; then
        fatal "Script only supports Proxmox VE."
    fi
}
function check_arch() {
    local arch=$(uname -m)
    if [[ $arch != "x86_64" ]]; then
        fatal "This script only supports x86_64."
    else
        check_ok "Architecture ${CBlue}$arch${ENDMARKER} supported"
    fi
}

function check_args() {
    if [[ ! "$PVE_SOURCE" ]]; then
        error "Source VM not specified | ${CBlue}--source <hostname>${ENDMARKER}
        "
        usage
        exit 1
    fi
    if [[ ! "$PVE_TARGET" ]]; then
        error "Target container name not specified | ${CBlue}--target <name>${ENDMARKER}
        "
        usage
        exit 1
    fi
    if [[ ! "$PVE_STORAGE" ]]; then
        error "Storage container name not specified | ${CBlue}--storage <name>${ENDMARKER}
        "
        usage
        exit 1
    fi
}

function create_container() {
    # Reference:
    # https://pve.proxmox.com/pve-docs/pct.1.html

    pct create $CT_NEXT_ID "$PVE_SOURCE_OUTPUT" \
        --description $PVE_DESCRIPTION \
        --hostname $PVE_TARGET \
        --arch $CT_ARCH \
        --cores $CT_CPU \
        --memory $CT_RAM \
        --rootfs $CT_HDD \
        --net0 $CT_NETWORKING \
        --ostype $CT_OSTYPE \
        --features $CT_FEATURES \
        --storage $PVE_STORAGE \
        --password $password \
        --unprivileged $CT_UNPRIVILEGED \
        --onboot $CT_ONBOOT
}

function map_ct_to_defaults() {
    # TODO: Override defaults with user specified options
    if [[ "$OPT_DEFAULT_CONFIG" -eq 1 ]]; then
        CT_CPU=$CT_DEFAULT_CPU
        CT_RAM=$CT_DEFAULT_RAM
        CT_HDD=$CT_DEFAULT_HDD
        CT_UNPRIVILEGED=$CT_DEFAULT_UNPRIVILEGED
        CT_NETWORKING=$CT_DEFAULT_NETWORKING
        CT_FEATURES=$CT_DEFAULT_FEATURES
        CT_ONBOOT=$CT_DEFAULT_ONBOOT
        CT_ARCH=$CT_DEFAULT_ARCH
        CT_OSTYPE=$CT_DEFAULT_OSTYPE    
    fi    
}

function print_opts() {
    msg "Gathering options..."
    msg3 "PVE Storage: ${CBlue}$PVE_STORAGE${ENDMARKER}"
    msg3 "Source VM:   ${CBlue}$PVE_SOURCE${ENDMARKER}"
    msg3 "- Output:    ${CCyan}$PVE_SOURCE_OUTPUT${ENDMARKER}"
    msg3 "- Cleanup:   ${CCyan}$OPT_CLEANUP${ENDMARKER}"
    msg3 "Target CT:   ${CBlue}$PVE_TARGET${ENDMARKER}"
    msg3 "CT Default:  ${CBlue}$OPT_DEFAULT_CONFIG${ENDMARKER}"
    if [ "$OPT_DEFAULT_CONFIG" -eq 1 ]; then
        msg3 "- ID:        ${CCyan}$CT_NEXT_ID${ENDMARKER}"
        msg3 "- ARCH:      ${CCyan}$CT_DEFAULT_ARCH${ENDMARKER}"
        msg3 "- CPU:       ${CCyan}$CT_DEFAULT_CPU${ENDMARKER}"
        msg3 "- RAM:       ${CCyan}$CT_DEFAULT_RAM${ENDMARKER}"
        msg3 "- HDD:       ${CCyan}$CT_DEFAULT_HDD${ENDMARKER}"
        msg3 "- OSTYPE:    ${CCyan}$CT_DEFAULT_OSTYPE${ENDMARKER}"
        msg3 "- NETWORK:   ${CCyan}$CT_DEFAULT_NETWORKING${ENDMARKER}"
        msg3 "- FEATURES:  ${CCyan}$CT_DEFAULT_FEATURES${ENDMARKER}"
        msg3 "- UNPRIV:    ${CCyan}$CT_DEFAULT_UNPRIVILEGED${ENDMARKER}"
        msg3 "- ONBOOT:    ${CCyan}$CT_DEFAULT_ONBOOT${ENDMARKER}"
    fi
    msg "Gathering options...Done!"
}
function validate_env() {    
    msg "Validating environment..."
    check_sudo
    check_arch
    check_shell
    check_proxmox
    check_proxmox_version
    check_proxmox_storage
    msg "Validating environment...done!"
}


main() {
    CT_NEXT_ID=$(pvesh get /cluster/nextid)
    TEMP_DIR=/tmp/proxmox-vm-to-ct/
        
    if [[ "$OPT_SOURCE_OUTPUT" ]]; then
        PVE_SOURCE_OUTPUT=$OPT_SOURCE_OUTPUT
    else
        PVE_SOURCE_OUTPUT=$TEMP_DIR/$PVE_SOURCE.tar.gz
    fi

    # Get the list of storage containers
    mapfile -t PVE_STORAGE_LIST < <(pvesm status -content images | awk -v OFS="\\n" -F " +" 'NR>1 {print $1}')

    print_opts
    validate_env
    map_ct_to_defaults

}

check_args

banner
check_pve
main "$@"
