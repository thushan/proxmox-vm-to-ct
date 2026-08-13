# Proxmox VM to Container - Technical Documentation

## Project Overview
Bash script that converts running Proxmox VMs to Containers via SSH tar snapshot streaming. Designed for Proxmox 7.x/8.x with special support for DietPi VMs.

## Core Conversion Flow
1. **Validation Phase**
   - Verify running on Proxmox host (`check_proxmox`)
   - Check storage availability (`check_proxmox_storage`)
   - Validate source VM (running state required)
   - Check dependencies (sshpass optional)

2. **SSH Snapshot Phase**
   - SSH into running VM (`create_vm_snapshot`)
   - Execute remote functions via serialized bash
   - Create tar archive excluding system dirs
   - Stream tar back to Proxmox host

3. **Container Creation Phase**
   - Use `pct create` with configuration
   - Apply container settings (CPU, RAM, disk, network)
   - Set features (nesting, keyctl for Docker)
   - Verify container creation

## Key Files
- **`proxmox-vm-to-ct.sh`** - Main conversion script (845 lines)
  - Functions: 60+ including validation, SSH, container creation
  - Error handling: trap cleanup on EXIT
  - Color output: tput-based terminal formatting
  
- **`default.config`** - Default container configuration
  - Standard: 2 CPU, 2GB RAM, 20GB disk
  - Unprivileged with nesting enabled
  - DHCP networking on vmbr0

## Critical Functions

### Main Workflow
- `main()` - Orchestrates entire conversion process
- `get_vm_snapshot()` - Determines snapshot method (SSH or file)
- `create_vm_snapshot()` - SSH execution and tar streaming
- `create_container()` - Proxmox container creation via pct

### Remote Execution
- `vm_fs_snapshot()` - Creates tar archive on VM
  - Excludes: sys, dev, run, proc, logs, swap
  - Uses: `tar -czvvmf - -C /`
- `vm_ct_prep()` - General VM preparation
- `vm_ct_prep_dietpi()` - DietPi-specific modifications
- `vm_ct_prep_cleanup()` - Installs the first-boot container cleanup unit (any systemd guest)

### Configuration
- `init_ct_config()` - Initialize container settings
- `load_ct_configuration()` - Parse config files
- `map_ct_to_defaults()` - Apply default configurations

### Validation
- `check_proxmox()` - Verify Proxmox environment
- `check_proxmox_storage()` - Validate storage exists
- `check_proxmox_container()` - Check container name availability
- `check_proxmox_version()` - Ensure PVE 7.x or 8.x

## Configuration System

### Default Profiles
1. **Standard** (`--default-config`)
   - Unprivileged container
   - Features: nesting=1
   - Network: DHCP on vmbr0

2. **Docker/Containerd** (`--default-config-containerd`)
   - Privileged container
   - Features: nesting=1,keyctl=1
   - Required for container runtimes

### Custom Configuration
- Format: KEY=VALUE pairs
- Required: Empty line at end of file
- Overridable: CPU, RAM, HDD, networking, features

## DietPi Optimizations
Detected via `/boot/dietpi/.version`:

1. **Hardware Model**: Set to 75 (container mode)
2. **First Boot**: Reset install stage to 1
3. **CloudShell**: Disable service

## Container Cleanup (not DietPi-specific)
Installed by `vm_ct_prep_cleanup()` as `/etc/systemd/system/proxmox-vm-to-ct-cleanup.service`
plus `/usr/local/sbin/proxmox-vm-to-ct-cleanup`, enabled by symlinking into
`multi-user.target.wants` rather than by invoking `systemctl` on the source VM.

Requires `systemd` on the guest. If `/etc/systemd/system` is absent, the
cleanup unit is not installed. The package purge additionally requires
`dpkg`/`apt`, so it covers the Debian family. On other systemd guests, the unit
still performs the `fstab` and `/boot/efi` steps.

Runs once, on the first boot **inside the container**, guarded by
`ConditionVirtualization=container` so it can never fire on the source VM. It:

1. **Package purge**: installed packages matching `linux-image-*`, `linux-headers-*`,
   `linux-base`, `initramfs-tools*`, `tiny-initramfs`, `dracut*`, `grub-*`, `grub2-*`,
   `shim-*`, `mokutil`, `efibootmgr`, `os-prober`, `qemu-guest-agent`, `open-vm-tools`.
   Matched at runtime, so BIOS and EFI VMs are both covered. Needs
   `--allow-remove-essential` because `grub-efi-amd64-signed` is dpkg-protected.
2. **fstab**: comments out entries naming a device, backup at `/etc/fstab.vm-to-ct.bak`
3. **ESP**: removes `/boot/efi` when it is not a mount point
4. **Self-removal**: only on success, so a failure retries on the next boot

## Remote Execution Pattern
Functions serialized for SSH execution:
```bash
ssh_command+=(
    "$(typeset -f vm_ct_prep); 
     $(typeset -f vm_ct_prep_dietpi); 
     $(typeset -f vm_ct_prep_cleanup);
     $(typeset -f vm_fs_snapshot); 
     $(declare -p OPT_IGNORE_DIETPI OPT_IGNORE_PREP); 
     vm_ct_prep; 
     vm_fs_snapshot"
)
```

## Error Handling
- **Global**: `set -Eeuo pipefail`
- **Cleanup**: trap cleanup EXIT
- **SSH Errors**: Captured to temp files
- **Fatal Errors**: `fatal()` function with colored output

## Command Line Options
- `--source`: VM hostname/IP or saved tar.gz
- `--target`: Container name
- `--storage`: Proxmox storage (local-lvm, etc.)
- `--source-output`: Save snapshot for reuse
- `--target-config`: Custom configuration file
- `--ignore-prep`: Skip VM modifications
- `--ignore-dietpi`: Skip DietPi-specific changes
- `--prompt-password`: Interactive password prompt

## Usage Examples

### Basic Conversion
```bash
./proxmox-vm-to-ct.sh --source vm.local --target my-ct \
                      --storage local-lvm --default-config
```

### Docker VM Conversion
```bash
./proxmox-vm-to-ct.sh --source docker-vm --target docker-ct \
                      --storage local-lvm --default-config-containerd
```

### Save & Reuse Snapshot
```bash
# Save snapshot
./proxmox-vm-to-ct.sh --source vm.local --target ct1 \
                      --storage local-lvm -o snapshot.tar.gz

# Reuse snapshot
./proxmox-vm-to-ct.sh --source snapshot.tar.gz --target ct2 \
                      --storage local-lvm --default-config
```

## Technical Details

### SSH Connection
- Default port: 22
- Default user: root
- Timeout: 10 seconds
- Password: sshpass support or interactive

### Container Settings
- Next ID: Auto-determined via `pvesh get /cluster/nextid`
- Password: Auto-generated 10 char or prompted
- Architecture: amd64 (default)
- OS Type: debian

### Tar Archive Exclusions
- System directories: /sys, /dev, /run, /proc
- Log files: *.log, *.log*
- Archives: *.gz, *.sql
- Swap: swap.img

## Testing Recommendations
1. Start with small test VMs
2. Create VM snapshot before conversion
3. Test SSH connectivity first
4. Verify storage has sufficient space
5. Check container starts and networking works

## Requirements
- **Host**: Proxmox VE 7.x or 8.x
- **Shell**: Bash 4.0+
- **Commands**: pvesh, pct, pvesm, tar, ssh
- **Optional**: sshpass for automated SSH auth
- **Source VM**: Must be running and SSH accessible

## Security Considerations
- Temporary password generated if not provided
- SSH passwords handled via sshpass or interactive
- Cleanup removes temporary files
- Container created with firewall enabled

## Performance Notes
- Tar compression: gzip level default
- Streaming reduces disk usage
- Progress shown via stderr redirect
- Real-time filename display during transfer

## Limitations
- AMD64 architecture only
- Debian-based containers
- Source VM must be running
- No incremental/differential snapshots
- Single network interface configuration

## Version History
- v1.3.0: Container cleanup for every guest, not just DietPi
- v1.1.1: sshpass support, improved SSH handling
- v1.0.0: File-based snapshot reuse
- v0.9.x: Initial release with DietPi support
