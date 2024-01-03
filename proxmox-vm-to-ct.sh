#!/usr/bin/env bash

# License: MIT
# Author: Thushan Fernando <thushan.fernando@gmail.com>
# http://www.github.com/thushan/proxmox-vm-to-ct

VERSION=0.0.1
PROXMOX_NEXTID=$(pvesh get /cluster/nextid)
TEMP_DIR=/tmp/proxmox-vm-to-ct/

set -Eeuo pipefail
#trap cleanup EXIT

CGrey=`tput setaf 239`
CBlack=`tput setaf 0`
CRed=`tput setaf 1`
CGreen=`tput setaf 2`
CDGreen=`tput setaf 034`
CYellow=`tput setaf 3`
CBlue=`tput setaf 4`
CMagenta=`tput setaf 5`
CCyan=`tput setaf 6`
CWhite=`tput setaf 7`
COrange=`tput setaf 202`
CProxmox=`tput setaf 166`
CDietPi=`tput setaf 112`
BOLD=`tput smso`
UNBOLD=`tput rmso`
ENDMARKER=`tput sgr0`

function banner() {
BANNER="
 ${CProxmox} ___             ${CWhite}               ${CDietPi} ___  _     _   ___ _ 
 ${CProxmox}| _ \_ _ _____ __${CWhite}_ __  _____ __ ${CDietPi}|   \(_)___| |_| _ (_)
 ${CProxmox}|  _/ '_/ _ \ \ /${CWhite} '  \/ _ \ \ / ${CDietPi}| |) | / -_)  _|  _/ |
 ${CProxmox}|_| |_| \___/_\_\\${CWhite}_|_|_\___/_\_\ ${CDietPi}|___/|_\___|\__|_| |_|

 ${CGrey}Virtual Machine${ENDMARKER} to ${CGrey}Container${ENDMARKER} Conversion Script  ${CYellow}v${VERSION}${ENDMARKER}
 ${CBlue}github.com/thushan/proxmox-vm-to-ct${ENDMARKER}

"
printf "$BANNER"
}

function msg() {
    echo "${CCyan}$1${ENDMARKER}"
}

function error() {
    echo "${BOLD}${CRed}ERROR:${UNBOLD}${ENDMARKER} $1${ENDMARKER}"
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
    echo "${BOLD}${CRed}FATAL:${UNBOLD}${ENDMARKER} $1${ENDMARKER}"
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
    if [ -n "${SSH_CLIENT:+x}" ]; then
        check_error "SSH Session detected"
        fatal "Please run on the Proxmox host, not within SSH"
    fi
    check_ok "Running on Proxmox host shell"
}

function check_proxmox_version(){
    local version=$(pveversion | grep -oP '(?<=pve-manager\/)[0-9]+')
    if [ "$version" -eq 7 ] || [ "$version" -eq 8 ]; then
        check_ok "Proxmox version ${CBlue}v$version.x${ENDMARKER} is supported"
    else
        check_error "Unsupported version v$version"
        fatal "Unsupported release of Proxmox."
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

banner

msg "Validating environment..."
check_sudo
check_arch
check_proxmox
check_proxmox_version
msg "Validating environment...done!"

