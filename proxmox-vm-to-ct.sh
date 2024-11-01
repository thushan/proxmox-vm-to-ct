#!/usr/bin/env bash

# License: MIT
# Author: Thushan Fernando <thushan.fernando@gmail.com>
# http://github.com/thushan/proxmox-vm-to-ct

VERSION=1.1.1

set -Eeuo pipefail
set -o nounset
set -o errexit
trap cleanup EXIT

if [[ "${TRACE-0}" == "1" ]]; then
    set -o xtrace
fi

PVE_SOURCE=""
PVE_SOURCE_PORT=22
PVE_SOURCE_USER=root
PVE_TARGET=""
PVE_STORAGE=""
PVE_SOURCE_OUTPUT=""
PVE_DESCRIPTION="Converted from VM to CT via <a href="http://www.github.com/thushan/proxmox-vm-to-ct">proxmox-vm-to-ct</a>."
PVE_SSH_PASSWORD=""

OPT_TARGET_CONFIG=""

OPT_SOURCE_TYPE=
OPT_SOURCE_TYPE_FILE=1
OPT_SOURCE_TYPE_SSH=2

OPT_IGNORE_SOURCE_VERIFY=0
OPT_DEFAULT_CONFIG=0
OPT_SOURCE_OUTPUT=""
OPT_IGNORE_PREP=0
OPT_IGNORE_DIETPI=0
OPT_PROMPT_PASS=0
INT_PROMPT_PASS=0

INT_HOST_DEP_SSHPASS=0

SSH_CONNECTION_TIMEOUT=5

# Used to determine whether to cleanup
# invalid templates or not
CT_SUCCESS=0
CT_SCREENP=0

# Defaults for CT
OPT_DEFAULTS_NONE=0
OPT_DEFAULTS_DEFAULT=1
OPT_DEFAULTS_CONTAINERD=2

CT_DEFAULT_CPU=2
CT_DEFAULT_RAM=2048
CT_DEFAULT_HDD=20
CT_DEFAULT_UNPRIVILEGED=1
CT_DEFAULT_NETWORKING="name=eth0,ip=dhcp,ip6=auto,bridge=vmbr0,firewall=1"
CT_DEFAULT_FEATURES="nesting=1"
CT_DEFAULT_ONBOOT=0
CT_DEFAULT_ARCH="amd64"
CT_DEFAULT_OSTYPE="debian"

CT_DEFAULT_DOCKER_UNPRIVILEGED=0
CT_DEFAULT_DOCKER_FEATURES="nesting=1,keyctl=1"

CT_CPU=$CT_DEFAULT_CPU
CT_RAM=$CT_DEFAULT_RAM
CT_HDD=$CT_DEFAULT_HDD
CT_UNPRIVILEGED=$CT_DEFAULT_UNPRIVILEGED
CT_NETWORKING=$CT_DEFAULT_NETWORKING
CT_FEATURES=$CT_DEFAULT_FEATURES
CT_ONBOOT=$CT_DEFAULT_ONBOOT
CT_ARCH=$CT_DEFAULT_ARCH
CT_OSTYPE=$CT_DEFAULT_OSTYPE

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
CPurple=$(tput setaf 171)
COrange=$(tput setaf 202)
CProxmox=$(tput setaf 166)
CDietPi=$(tput setaf 112)
BOLD=$(tput smso)
UNBOLD=$(tput rmso)
ENDMARKER=$(tput sgr0)

LINES=$(tput lines)
COLUMNS=$(tput cols)

function banner() {
    local STYLE=${1:-0}

    local SUB_HEADING=''
    local FOOTER=''

    if [[ "$STYLE" -eq 0 ]]; then
        SUB_HEADING="%-6s${CBlue}github.com/thushan/proxmox-vm-to-ct${ENDMARKER}%-4s${CYellow}v${VERSION}${ENDMARKER}"
        FOOTER="
   Your ${CGrey}Virtual Machine${ENDMARKER} to ${CGrey}Container${ENDMARKER} Conversion Script

"
    elif [[ "$STYLE" -eq 1 ]]; then
        SUB_HEADING=$(printf "%-6s%-50s%s" "" "${CGreen}> ${CBlue}$PVE_SOURCE" "${CYellow}| SSH${ENDMARKER}")
        FOOTER=""
    fi

    BANNER=" ${CWhite} ___             ${CWhite}               ${CDietPi} ___  _     _   ___ _
 ${CWhite}| _ \_ _ ___${CProxmox}__ __${CWhite}_ __  ___${CProxmox}__ __ ${CDietPi}|   \(_)___| |_| _ (_)
 ${CWhite}|  _/ '_/ _ ${CProxmox}\ \ /${CWhite} '  \/ _ ${CProxmox}\ \ / ${CDietPi}| |) | / -_)  _|  _/ |
 ${CWhite}| | |_| \___${CProxmox}/_\_\\${CWhite}_|_|_\___${CProxmox}/_\_\ ${CDietPi}|___/|_\___|\__|_| |_|
 ${CWhite}|_|$SUB_HEADING
$FOOTER"
    printf "$BANNER"
}

function msg() {
    echo "${CMagenta}$1${ENDMARKER}"
}
function msg_done() {
    echo "${CMagenta}$1${ENDMARKER}${CGreen}Done!${ENDMARKER}"
}
function msg2() {
    echo "${CCyan}$1${ENDMARKER}"
}
function msg3() {
    echo "${CWhite}$1${ENDMARKER}"
}
function msg4() {
    echo "${CYellow}$1${ENDMARKER}"
}
function msg_default() {
    echo "$1"
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
function fatal-script() {
    fatal "Exiting script..."
}
function fatal() {
    echo ""
    echo "${BOLD}${CRed}FATAL:${UNBOLD}${ENDMARKER} $1${ENDMARKER}" >&2
    echo ""
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
    if [[ ${PVE_STORAGE_LIST[*]} =~ $PVE_STORAGE ]]; then
        check_ok "Storage ${CBlue}$PVE_STORAGE${ENDMARKER} found"
    else
        IFS=,
        check_error "Storage ${CBlue}$PVE_STORAGE${ENDMARKER} not found (detected: ${CBlue}$(
            IFS=,
            echo "${PVE_STORAGE_LIST[*]}"
        )${ENDMARKER})"
        fatal "Please specify a valid storage name"
    fi
}

function check_container_settings() {
    if [[ "$CT_UNPRIVILEGED" -eq 1 ]]; then
        check_info "Creating ${CGreen}UNPRIVILLEGED${ENDMARKER} container."
    elif [[ $CT_UNPRIVILEGED -eq 0 ]]; then
        check_info "Creating ${CRed}PRIVILLEGED${ENDMARKER} container."
    fi
}

function check_proxmox_container() {
    local containers=$(pct list | awk 'NR>1 {print $NF}')
    if [[ ${containers[*]} =~ $PVE_TARGET ]]; then
        check_error "Container ${CBlue}$PVE_TARGET${ENDMARKER} already exists"
        fatal "Please specify a different container name"
    else
        check_ok "Container ${CBlue}$PVE_TARGET${ENDMARKER} unique"
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
function check_deps() {
    if [[ ! -x "$(command -v sshpass)" ]]; then
        check_warn "No '${CBlue}sshpass${ENDMARKER}' detected. (Try: ${CCyan}sudo apt install sshpass${ENDMARKER})"
        INT_HOST_DEP_SSHPASS=0
    else
        INT_HOST_DEP_SSHPASS=1
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

function check_proxmox_vm_source() {

    if [[ -f "$PVE_SOURCE" ]]; then
        # check for a valid *.tar.gz
        check_info "Using source image ${CBlue}$(basename ${PVE_SOURCE})${ENDMARKER}, checking integrity..."
        if [[ "$OPT_IGNORE_SOURCE_VERIFY" -eq 0 ]]; then
            if gzip -t "$PVE_SOURCE" &>/dev/null; then
                check_ok "Verified source image ${CBlue}$(basename ${PVE_SOURCE})${ENDMARKER}"
            else
                check_error "Invalid source image ${CBlue}$(basename ${PVE_SOURCE})${ENDMARKER}"
                fatal "Please try another source image"
            fi
        else
            check_warn "Verifying source image skipped"
        fi
    fi
    if ! [[ "$PVE_SOURCE_PORT" =~ ^[0-9]+$ ]] || [ "$PVE_SOURCE_PORT" -lt 1 ] || [ "$PVE_SOURCE_PORT" -gt 65535 ]; then
        check_error "Invalid SSH Port number specified ${CRed}$PVE_SOURCE_PORT${ENDMARKER}..."
        fatal "Please set an SSH Port number between 1 and 65535"
    else
        check_ok "SSH Port ${CBlue}$PVE_SOURCE_PORT${ENDMARKER} valid."
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
    if [[ ! -z "$OPT_TARGET_CONFIG" ]] && [[ ! -f "$OPT_TARGET_CONFIG" ]]; then
        error "Target Configuration file '${CYellow}${OPT_TARGET_CONFIG}${ENDMARKER}' not found.
        "
        usage
        exit 1
    fi
}

function create_container() {
    # Reference:
    # https://pve.proxmox.com/pve-docs/pct.1.html

    local c_status="Creating Container..."

    msg "$c_status"
    pct create $CT_NEXT_ID "$PVE_SOURCE_OUTPUT" \
        --description "$PVE_DESCRIPTION" \
        --hostname "$PVE_TARGET" \
        --arch "$CT_ARCH" \
        --cores $CT_CPU \
        --memory $CT_RAM \
        --rootfs $CT_HDD \
        --net0 $CT_NETWORKING \
        --ostype "$CT_OSTYPE" \
        --features "$CT_FEATURES" \
        --storage $PVE_STORAGE \
        --password "$CT_PASSWORD" \
        --unprivileged $CT_UNPRIVILEGED \
        --onboot $CT_ONBOOT
    msg_done "$c_status"
}

function init_ct_config() {

    map_ct_to_defaults

    # If we're here, we know this exists now
    if [[ -n "$OPT_TARGET_CONFIG" ]]; then
        load_ct_configuration "$OPT_TARGET_CONFIG"
    fi

}

function map_ct_to_defaults() {

    # They didn't specify a default, so let's not load any
    if [[ "$OPT_DEFAULT_CONFIG" -eq $OPT_DEFAULTS_NONE ]]; then
        return
    fi

    # Set base defaults
    CT_CPU=$CT_DEFAULT_CPU
    CT_RAM=$CT_DEFAULT_RAM
    CT_HDD=$CT_DEFAULT_HDD
    CT_UNPRIVILEGED=$CT_DEFAULT_UNPRIVILEGED
    CT_NETWORKING=$CT_DEFAULT_NETWORKING
    CT_FEATURES=$CT_DEFAULT_FEATURES
    CT_ONBOOT=$CT_DEFAULT_ONBOOT
    CT_ARCH=$CT_DEFAULT_ARCH
    CT_OSTYPE=$CT_DEFAULT_OSTYPE

    if [[ "$OPT_DEFAULT_CONFIG" -eq $OPT_DEFAULTS_CONTAINERD ]]; then
        CT_UNPRIVILEGED=$CT_DEFAULT_DOCKER_UNPRIVILEGED
        CT_FEATURES=$CT_DEFAULT_DOCKER_FEATURES
    fi
}
function load_ct_configuration()
{
    local config="$1"
    local c_status="Loading Configuration..."

    msg "$c_status"
    while IFS="=" read -r key value; do
    # Trim in leading/trailing quotes
    value="${value#\"}"; value="${value%\"}"
    value="${value#\'}"; value="${value%\'}"
    case "$key" in
        "CT_CPU") CT_CPU="$value" ;;
        "CT_RAM") CT_RAM="$value" ;;
        "CT_HDD") CT_HDD="$value" ;;
        "CT_UNPRIVILEGED") CT_UNPRIVILEGED="$value" ;;
        "CT_NETWORKING") CT_NETWORKING="$value" ;;
        "CT_FEATURES") CT_FEATURES="$value" ;;
        "CT_ONBOOT") CT_ONBOOT="$value" ;;
        "CT_ARCH") CT_ARCH="$value" ;;
        "CT_OSTYPE") CT_OSTYPE="$value" ;;
    esac
    done < "$config"
    msg_done "$c_status"
}
function print_opts() {
    local c_status="Gathering options..."
    local CT_SECURE_PASSWORD="**********"
    local CT_DEFAULT_CONFIG_TYPE=""

    if [[ "$OPT_PROMPT_PASS" -eq 0 ]] && [[ "$INT_PROMPT_PASS" -eq 0 ]]; then
        CT_SECURE_PASSWORD=$CT_PASSWORD
    fi

    if [[ "$OPT_DEFAULT_CONFIG" -eq $OPT_DEFAULTS_CONTAINERD ]]; then
        CT_DEFAULT_CONFIG_TYPE="containerd / docker"
    elif [[ "$OPT_DEFAULT_CONFIG" -eq $OPT_DEFAULTS_DEFAULT ]]; then
        CT_DEFAULT_CONFIG_TYPE="default"
    fi

    if [[ ! -z "$OPT_TARGET_CONFIG" ]]; then
        CT_DEFAULT_CONFIG_TYPE="$CT_DEFAULT_CONFIG_TYPE + $OPT_TARGET_CONFIG"
    fi

    msg "$c_status"
    msg3 "PVE Storage:      ${CBlue}$PVE_STORAGE${ENDMARKER}"
    msg3 "Source VM:        ${CBlue}$PVE_SOURCE${ENDMARKER}"
    if [[ "$OPT_SOURCE_TYPE" -eq $OPT_SOURCE_TYPE_SSH ]]; then
        msg3 "- Output:         ${CCyan}$PVE_SOURCE_OUTPUT${ENDMARKER}"
    fi
    msg3 "Target CT:        ${CBlue}$PVE_TARGET${ENDMARKER}"
    msg3 "- Password:       ${CRed}$CT_SECURE_PASSWORD${ENDMARKER}"
    msg3 "Target Config:    ${CBlue}$CT_DEFAULT_CONFIG_TYPE${ENDMARKER}"
    msg3 "- ID:             ${CCyan}$CT_NEXT_ID${ENDMARKER}"
    msg3 "- ARCH:           ${CCyan}$CT_ARCH${ENDMARKER}"
    msg3 "- CPU:            ${CCyan}$CT_CPU${ENDMARKER}"
    msg3 "- RAM:            ${CCyan}$CT_RAM${ENDMARKER}"
    msg3 "- HDD:            ${CCyan}$CT_HDD${ENDMARKER}"
    msg3 "- OSTYPE:         ${CCyan}$CT_OSTYPE${ENDMARKER}"
    msg3 "- NETWORK:        ${CCyan}$CT_NETWORKING${ENDMARKER}"
    msg3 "- FEATURES:       ${CCyan}$CT_FEATURES${ENDMARKER}"
    msg3 "- UNPRIV:         ${CCyan}$CT_UNPRIVILEGED${ENDMARKER}"
    msg3 "- ONBOOT:         ${CCyan}$CT_ONBOOT${ENDMARKER}"
    msg_done "$c_status"
}
function validate_env() {
    local c_status="Checking environment..."
    msg "$c_status"
    check_sudo
    check_arch
    check_deps
    check_shell
    check_proxmox
    check_proxmox_version
    check_proxmox_storage
    check_proxmox_container
    check_proxmox_vm_source
    check_container_settings
    msg_done "$c_status"
}

function created_container_verify() {
    local c_status="Checking Container ${CBlue}$PVE_TARGET${ENDMARKER}..."
    msg "$c_status"
    local containers=$(pct list | awk 'NR>1 {print $NF}')
    if [[ ${containers[*]} =~ $PVE_TARGET ]]; then
        check_ok "Container ${CBlue}$PVE_TARGET${ENDMARKER} created :)"
        CT_SUCCESS=1
    else
        check_error "Container ${CBlue}$PVE_TARGET${ENDMARKER} failed to create :("
        fatal "Container creation failed, check output above or log a bug!"
    fi
    msg_done "$c_status"
}
function created_container_print_opts() {
    local CT_SECURE_PASSWORD="¯\_(ツ)_/¯"

    if [[ "$OPT_PROMPT_PASS" -eq 0 ]] && [[ "$INT_PROMPT_PASS" -eq 0 ]]; then
        CT_SECURE_PASSWORD=$CT_PASSWORD
    fi

    local template_size=$(du -h "$PVE_SOURCE_OUTPUT" | cut -f1)

    msg4 "=== '${CBlue}$PVE_TARGET${ENDMARKER}${CYellow}' Summary ===${ENDMARKER}"
    msg3 "Container:        ${CBlue}$PVE_TARGET${ENDMARKER}"
    msg3 "- ID:             ${CCyan}$CT_NEXT_ID${ENDMARKER}"
    msg3 "- Password:       ${CRed}$CT_SECURE_PASSWORD${ENDMARKER}"
    msg3 "- Storage:        ${CCyan}$PVE_STORAGE${ENDMARKER}"
    msg3 "- Template:       ${CCyan}$PVE_SOURCE_OUTPUT ($template_size)${ENDMARKER}"
    msg4 "Start it up with: ${CGreen}pct start $CT_NEXT_ID${ENDMARKER}"
}

function color_cat() {
    if [ -f "$1" ]; then
        cat "$1" | sed "s/.*/\x1b[37m&\x1b[0m/"
    fi
}
function vm_ct_prep() {
    if [[ "$OPT_IGNORE_PREP" -eq 1 ]]; then
        return
    fi
    vm_ct_prep_dietpi
}

function vm_ct_prep_dietpi() {
    local dietpi_version=/boot/dietpi/.version

    # Check for the existence of DietPi version file & bail if we can't find it
    if [[ "$OPT_IGNORE_DIETPI" -eq 1 || ! -f "$dietpi_version" ]]; then
        return
    fi

    # Tell DietPi we're in a container
    # src: https://github.com/MichaIng/DietPi/blob/master/dietpi/func/dietpi-obtain_hw_model#L27
    echo 75 > /etc/.dietpi_hw_model_identifier

    # Ensure DietPi installs updates & sets passwords for CT
    # by going back to install_stage 1 (it'll be 2 now)
    echo 1 > /boot/dietpi/.install_stage

    # Disable CloudShell, interferes with CT
    local DPI_CLOUDSHELL_SERVICE_PATH=/etc/systemd/system/dietpi-cloudshell.service
    local DPI_CLOUDSHELL_SERVICE_NAME=dietpi-cloudshell

    if [ -e $DPI_CLOUDSHELL_SERVICE_PATH ]; then
        if systemctl is-enabled --quiet "$DPI_CLOUDSHELL_SERVICE_NAME"; then
            systemctl stop "$DPI_CLOUDSHELL_SERVICE_NAME"
        fi
        systemctl disable --now "$DPI_CLOUDSHELL_SERVICE_NAME"
        rm -f "$DPI_CLOUDSHELL_SERVICE_PATH"
        systemctl daemon-reload
    fi

    # Purge unnecessary packages, this may grow in the future, but simples for now.
    echo "apt autopurge -y grub-pc tiny-initramfs linux-image-amd64" > /boot/Automation_Custom_Script.sh
}

function vm_fs_snapshot() {
    # credit https://github.com/my5t3ry/machine-to-proxmox-lxc-ct-converter/blob/master/convert.sh#L53
    tar -czvvmf - -C / \
        --exclude="sys" \
        --exclude="dev" \
        --exclude="run" \
        --exclude="proc" \
        --exclude="*.log" \
        --exclude="*.log*" \
        --exclude="*.gz" \
        --exclude="*.sql" \
        --exclude="swap.img" \
        .
}

function get_vm_snapshot() {
    if [[ "$OPT_SOURCE_TYPE" -eq "$OPT_SOURCE_TYPE_SSH" ]]; then
        create_vm_snapshot
    fi
}

function create_vm_snapshot() {
    local c_status="${CMagenta}SSH Session:${ENDMARKER} ${CBlue}$PVE_SOURCE${ENDMARKER}..."

    msg "$c_status"

    cursor_save
    CT_SCREENP=1

    tput clear
    tput cup 0 0
    banner 1

    ssh_err_out="$TEMP_DIR/$PVE_SOURCE-ssh.err"
    ssh_tmp_out="$TEMP_DIR/$PVE_SOURCE-ssh.tmp"
    ssh_command=(ssh -p "$PVE_SOURCE_PORT" -o "ConnectTimeout=$SSH_CONNECTION_TIMEOUT" "$PVE_SOURCE_USER@$PVE_SOURCE")
    ssh_command+=(
        "$(typeset -f vm_ct_prep); $(typeset -f vm_ct_prep_dietpi); $(typeset -f vm_fs_snapshot); $(declare -p OPT_IGNORE_DIETPI OPT_IGNORE_PREP); vm_ct_prep; vm_fs_snapshot"
    )

    # Clear previous error output
    > "$ssh_err_out"

    set +e # Temporarily disable to handle SSH woes
    if [ -n "$PVE_SSH_PASSWORD" ]; then
        SSHPASS="$PVE_SSH_PASSWORD" sshpass -e "${ssh_command[@]}" 2> >(tee "$ssh_err_out" >&2) > "$ssh_tmp_out" &
    else
        "${ssh_command[@]}" 2> >(tee "$ssh_err_out" >&2) > "$ssh_tmp_out" &
    fi
    ssh_pid=$!

    # This is to be able to see the filenames in realtime
    tail -f "$ssh_err_out" | sed -u 's/^.*\r//; /^\.\/$/d; s/^\.\//./' &
    tail_pid=$!

    # Wait for SSH to complete
    wait $ssh_pid
    ssh_status=$?

    # Stop the tail process
    kill $tail_pid 2>/dev/null
    wait $tail_pid 2>/dev/null

    set -e # reenable

    cursor_restore
    CT_SCREENP=0

    if [ $ssh_status -ne 0 ]; then
        error "SSH to ${CYellow}$PVE_SOURCE_USER@$PVE_SOURCE:$PVE_SOURCE_PORT${ENDMARKER} failed with status: ${BOLD}$ssh_status${ENDMARKER}"
        error "Error output saved to '${CBlue}$ssh_err_out${ENDMARKER}':"
        color_cat "$ssh_err_out"
        rm -f "$ssh_tmp_out"
        fatal "Aborting."
    else
        # Only move the file if SSH was successful
        mv "$ssh_tmp_out" "$PVE_SOURCE_OUTPUT"
    fi
    msg_done "$c_status"
}
function cursor_save() {
    tput smcup
    tput sc
    tput csr 5 $(($LINES - 2))
}
function cursor_restore() {
    tput rmcup
    tput csr 0 $(($LINES - 1))
    tput rc
}
function prompt_password() {

    if PROMPT_PASS=$(whiptail --passwordbox "Enter a Password for '$PVE_TARGET'. \n(leave empty for a random one)" --title "Choose a strong password" 10 50 --cancel-button Exit 3>&1 1>&2 2>&3); then
        if [ -z "${PROMPT_PASS}" ]; then
            CT_PASSWORD=$TEMP_PASS
            INT_PROMPT_PASS=0
        else
            CT_PASSWORD=$PROMPT_PASS
            INT_PROMPT_PASS=1
        fi
    else
        fatal-script
    fi
}
function prompt_ssh_password() {
    # Dependency check first
    if [[ "$INT_HOST_DEP_SSHPASS" -eq 0 ]]; then
        PVE_SSH_PASSWORD=""
        return
    fi
    if PROMPT_SSH_PASS=$(whiptail --passwordbox "Enter the password for '$PVE_SOURCE_USER@$PVE_SOURCE'. \n(leave empty for a prompt from SSH later)" --title "Source PVE SSH Credentials" 10 50 --cancel-button Exit 3>&1 1>&2 2>&3); then
        if [ -z "${PROMPT_SSH_PASS}" ]; then
            PVE_SSH_PASSWORD=""
        else
            PVE_SSH_PASSWORD=$PROMPT_SSH_PASS
        fi
    else
        fatal-script
    fi
}
function ensure_env() {
    local c_status="Creating environment..."
    msg "$c_status"
    mkdir -p $TEMP_DIR
    msg_done "$c_status"
}

function get_vm_id_from_name() {
    local vm_name="$1"
    pvesh get /cluster/resources --type vm --output-format yaml | grep -Ei 'vmid|name' | grep -A1 "$vm_name" | grep 'vmid' | awk -F ':' '{print $2}'
}
function get_vm_mac_from_id() {
    local vm_id="$1"
    qm config "$vm_id" | grep 'net0:' | awk -F '=' '{print tolower($2)}' | awk -F ',' '{print $1}'
}

function get_vm_ip_from_mac() {
    local vm_mac="$1"
    ip neigh show | grep "$vm_mac" | awk '{print $1}'
}

function get_vm_ip_from_name() {
    local vm_name="$1"
    local vm_id
    local vm_mac

    vm_id=$(get_vm_id_from_name "$vm_name")
    vm_mac=$(get_vm_mac_from_id $vm_id)

    get_vm_ip_from_mac "$vm_mac"
}

function cleanup () {
    # https://www.youtube.com/watch?v=4F4qzPbcFiA
    local c_status="Cleaning up..."
    local template_size_before=0
    local source_path=""

    if [[ -f "$PVE_SOURCE_OUTPUT" ]]; then
        template_size_before=$(du -h "$PVE_SOURCE_OUTPUT" | cut -f1)
        source_path=$PVE_SOURCE_OUTPUT
    elif [[ -f "$PVE_SOURCE" ]]; then
        template_size_before=$(du -h "$PVE_SOURCE" | cut -f1)
        source_path=$PVE_SOURCE_OUTPUT
    fi

    # Reset screen & cursor position
    if [[ "$CT_SCREENP" -eq 1 ]]; then
        cursor_restore
    fi

    msg "$c_status"
    check_ok "Leaving  ${CBlue}$source_path${ENDMARKER} ($template_size_before)"
    msg_done "$c_status"
}

function resolve_pve_source() {
    if [[ -f "$PVE_SOURCE" ]]; then
        OPT_SOURCE_TYPE=$OPT_SOURCE_TYPE_FILE
        PVE_SOURCE_OUTPUT=$PVE_SOURCE
    else
        OPT_SOURCE_TYPE=$OPT_SOURCE_TYPE_SSH

        if [[ "$OPT_SOURCE_OUTPUT" ]]; then
            PVE_SOURCE_OUTPUT=$OPT_SOURCE_OUTPUT
        else
            PVE_SOURCE_OUTPUT=$TEMP_DIR/$PVE_SOURCE.tar.gz
        fi
    fi
}

function resolve_cte_password() {

    if [[ "$OPT_PROMPT_PASS" -eq 1 ]]; then
        prompt_password
    else
        CT_PASSWORD=$TEMP_PASS
    fi

}
function main() {
    CT_NEXT_ID=$(pvesh get /cluster/nextid)
    TEMP_DIR=/tmp/proxmox-vm-to-ct
    TEMP_PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 10; echo)

    resolve_pve_source
    resolve_cte_password

    # Get the list of storage containers
    mapfile -t PVE_STORAGE_LIST < <(pvesm status -content images | awk -v OFS="\\n" -F " +" 'NR>1 {print $1}')

    init_ct_config

    print_opts
    validate_env
    ensure_env
    get_vm_snapshot
    create_container
    created_container_verify
    created_container_print_opts
    # cleanup is called via trap, so no need to call it here
}

function usage() {
    banner 0
    echo "Usage: ${CYellow}$0${ENDMARKER} ${CBlue}--storage${ENDMARKER} <name> ${CBlue}--source${ENDMARKER} <hostname|file> ${CBlue}--target${ENDMARKER} <name> [options]"
    echo "Options:"
    echo "  ${CCyan}--storage${ENDMARKER} <name>"
    echo "      Name of the Proxmox Storage container (Eg. local-zfs, local-lvm, etc)"
    echo "  ${CCyan}--source${ENDMARKER} <hostname> | <file: *.tar.gz>"
    echo "      Source VM to convert to CT (Eg. postgres-vm.fritz.box or 192.168.0.10, source-vm.tar.gz file locally)"
    echo "  ${CCyan}--source-user${ENDMARKER} <username>"
    echo "      Source VM's SSH username to connect with. (Eg. ${CGreen}root${ENDMARKER}) "
    echo "  ${CCyan}--source-port${ENDMARKER} <port>"
    echo "      Source VM's SSH port to connect to. (Eg. ${CGreen}22${ENDMARKER}) "
    echo "  ${CCyan}--source-output${ENDMARKER} <path>, ${CCyan}--output${ENDMARKER} <path>, ${CCyan}-o${ENDMARKER} <path>"
    echo "      Location of the source VM output (default: ${CGreen}/tmp/proxmox-vm-to-ct/<hostname>.tar.gz${ENDMARKER})"
    echo "  ${CCyan}--target${ENDMARKER} <name>"
    echo "      Name of the container to create (Eg. postgres-ct)"
    echo "  ${CCyan}--target-config${ENDMARKER} <path>"
    echo "      Path to target configuration, for an example see ${CGreen}default-config.env${ENDMARKER}"
    echo "  ${CCyan}--default-config${ENDMARKER}"
    echo "      Default configuration for container (2 CPU, 2GB RAM, 20GB Disk)"
    echo "  ${CCyan}--default-config-containerd${ENDMARKER}, ${CCyan}--default-config-docker${ENDMARKER}"
    echo "      Default configuration for containerd containers (default + privileged, features: nesting, keyctl)"
    echo "  ${CCyan}--ignore-prep${ENDMARKER}"
    echo "      Ignore modifying the VM before snapshotting"
    echo "  ${CCyan}--ignore-dietpi${ENDMARKER}"
    echo "      Ignore DietPi specific modifications on the VM before snapshotting. (ignored with --ignore-prep)"
    echo "  ${CCyan}--ignore-source-verify${ENDMARKER}"
    echo "      Ignore Source Archive verification step."
    echo "  ${CCyan}--prompt-password${ENDMARKER}"
    echo "      Prompt for a password for the container, temporary one generated & displayed otherwise"
    echo "  ${CCyan}--help${ENDMARKER}"
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
    --source-port)
        PVE_SOURCE_PORT=$2
        shift
        ;;
    --source-user)
        PVE_SOURCE_USER=$2
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
    -o | --output | --source-output)
        OPT_SOURCE_OUTPUT="$2"
        shift
        ;;
    --target-config)
        OPT_TARGET_CONFIG="$2"
        shift
        ;;
    --default-config)
        OPT_DEFAULT_CONFIG=$OPT_DEFAULTS_DEFAULT
        ;;
    --default-config-containerd | --default-config-docker)
        OPT_DEFAULT_CONFIG=$OPT_DEFAULTS_CONTAINERD
        ;;
    --ignore-prep)
        OPT_IGNORE_PREP=1
        ;;
    --ignore-dietpi)
        OPT_IGNORE_DIETPI=1
        ;;
    --ignore-source-verify)
        OPT_IGNORE_SOURCE_VERIFY=1
        ;;
    --prompt-password)
        OPT_PROMPT_PASS=1
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

check_args

banner 0
check_pve
main "$@"
