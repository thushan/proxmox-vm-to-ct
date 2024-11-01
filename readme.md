# Proxmox VM to Container

<div align="center">

![Proxomx DietPi VM to Container](artefacts/logo.png)

[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](https://opensource.org/licenses/MIT)
![Updated](https://img.shields.io/github/last-commit/thushan/proxmox-vm-to-ct)
![Version](https://img.shields.io/badge/Version-v1.1.1-blue)
![Proxmox](https://img.shields.io/badge/Proxmox-7.x%20%7C%208.x-orange?logo=proxmox)
![DietPi](https://img.shields.io/badge/DietPi-6.x%20%7C%207.x%20%7C%208.x%20%7C%209.x-C1FF00?logo=dietpi)

</div>

This repository contains scripts and helpers to convert your [Proxmox](https://www.proxmox.com) VM's to containers - with a special emphasis on [DietPi](https://dietpi.com/) VMs, but [the tweaks for DietPi](#dietpi-changes) are ignored on non-DietPi distributions.

## How to use

Clone the repository with `git`, mark the script as executable and you're on your way!

```shell
git clone https://github.com/thushan/proxmox-vm-to-ct.git
cd proxmox-vm-to-ct
chmod +x ./proxmox-vm-to-ct.sh
```

No git? No problemo, just `wget` it.

```shell
wget https://raw.githubusercontent.com/thushan/proxmox-vm-to-ct/main/proxmox-vm-to-ct.sh
chmod +x ./proxmox-vm-to-ct.sh
```

Once downloaded, to create an container for the vm with the hostname `the-matrix` named `matrix-reloaded` with the [default CT configuration](#default-configuration) on your pve storage `local-zfs`:

```shell
./proxmox-vm-to-ct.sh --source the-matrix \
                      --target matrix-reloaded \
                      --storage local-zfs \
                      --default-config
```

If your VM has docker, podman or containerd installed, use the `--default-config-containerd` that sets up [default containerd configuration](#default-configuration---containerd--docker--podman):

```
./proxmox-vm-to-ct.sh --source the-matrix \
                      --target matrix-reloaded \
                      --storage local-zfs \
                      --default-config-containerd
```

You can use the fully qualified host name (Eg. `the-matrix` or `the-matrix.fritz.box`) or the IP (Eg. `192.168.0.101`) of the source VM you want to convert. Make sure the source VM is running as we SSH in.

See further [examples](#Examples) below.

> \[!TIP]
>
> If you want to retain the files for later, you can use the `--source-output` argument with a path to save it elsewhere.
>
> Eg. `--source-output ~/dietpi-first-attempt.tar.gz`
>
> Otherwise it will be created in your /tmp/proxmox-vm-to-ct folder.
>
> Next time you can reuse the above to create more containers by passing in the filename as the source.
>
> See examples below.

## Example Run

Creating a container named `hello-world` from a dockerised VM `192.168.0.199`, with an auto-generated password & default containerd options that's stored in `local-lvm`:

![Proxmox Run](artefacts/full-run-v0.9.x.png)

Now, you can start it up via `$ pct start 101` & login with the password above - ssh don't tell anyone!

## The Process

1. Install your 'base' image as a VM (be it DietPi or Debian etc.) on Proxmox as normal.

   You could opt to use [@dazeb/proxmox-dietpi-installer](https://github.com/dazeb/proxmox-dietpi-installer) to automate it.

   * Configure the VM with the core tools you'd like.
     * Eg. Tools `vim`, `tmux` etc.
     * Eg. Settings region, network, wifi etc.
     * Eg. Configuration `.bashrc`, `.tmux.conf` etc.
1. Run the `proxmox-vm-to-ct.sh` script (described below) to create a Container image from the VM.
2. Start your fancy new containerised VM!

## Creating your Base VM

Create a Proxmox VM with any VM configuration you like for your base VM - so 2-cores, 1GB RAM, 8GB disk for example, but your real container may be 16-core, 32GB RAM, 320GB Disk. Ensure that you install all the basic tools you need (for example, install `tmux` and update the `~/.bashrc` to start `tmux`) as well as any operating system configuration changes (Eg. locale).

Next, create a Proxmox Snapshot of your base VM - in case you want to change it later.

![Proxmox VM Snapshot](artefacts/intro-proxmoxvm-snapshot.png)

Now you're ready to create your Container. Remember, if you find anything goes wrong, you can revert to this clean snapshot and try again :-)

## Proxmox VM To CT

The `proxmox-vm-to-ct.sh` script takes a few arguments to create a container from your VM.

> \[!IMPORTANT]
>
> The VM you're trying to convert must be running, so ensure it's started.

### Examples

> \[!TIP]
>
> You can use the hostname (eg. `the-matrix.local`) or the IP itself for the source VM (`192.168.0.101`), either way
> you're going to have to SSH into the box!

#### Custom Configurations

You can specify your own Proxmox CT Configuration by creating a configuration file like below - eg. `hexa-core.config`:

```env
CT_CPUS=8
CT_RAM=10240

```

> \[!IMPORTANT]
>
> Configuration files **MUST** have a blank empty line at the end.
>
> You can comment lines with a `# this is a comment`

Then pass that to the script:

```
./proxmox-vm-to-ct.sh --storage local-lvm \
                      --source 192.168.0.152 \
                      --target the-matrix-reloaded \
                      --target-config hexa-core.config
```

Other configuration items will be loaded from the [default configuration](#default-configuration), however if you want to overide with say, the [docker/containerd configuration](#default-configuration---containerd--docker--podman), you can pass in a default config switch:

```
./proxmox-vm-to-ct.sh --storage local-lvm \
                      --source 192.168.0.152 \
                      --target the-matrix-reloaded \
                      --target-config hexa-core.config \
                      --default-config-containerd
```

For all the configuration options, see [default.config](./default.config).

#### Saving Source Output

For a running VM named `the-matrix-sql` (with ID: `100`; IP: `192.168.0.152`), to create a (default) container named `the-matrix-reloaded` on a Proxmox Server where the storage container is named `local-lvm` but store the created image for future use in you home folder:

```
./proxmox-vm-to-ct.sh --source 192.168.0.152 \
                      --target the-matrix-reloaded \
                      --storage local-lvm \
                      --default-config \
                      -o ~/proxmox-dietpi.tar.gz
```

#### Reusing Source Output

Once you [save a snapshot of a VM](#saving-source-output), you can reuse that to create more containers by using the `--source` switch and passing in the `*.tar.gz` file.

Step 1 - create your image

```
./proxmox-vm-to-ct.sh --source 192.168.0.152 \
                      --target the-matrix-reloaded \
                      --storage local-lvm \
                      --default-config \
                      -o ~/proxmox-dietpi.tar.gz
```

Step 2 - reuse your image

```
./proxmox-vm-to-ct.sh --source ~/proxmox-dietpi.tar.gz \
                      --target the-matrix-revolutions \
                      --storage local-lvm \
                      --default-config
```

This is supported in v1.0+ only and all archives will be verified before being used.

#### Skipping Source Image Verification

All source images used to create CT's are verified, but you can skip with `--ignore-source-verify`.

```
./proxmox-vm-to-ct.sh --source ~/proxmox-dietpi.tar.gz \
                      --target the-matrix-revolutions \
                      --storage local-lvm \
                      --default-config \
                      --ignore-source-verify
```

This isn't recommended unless you intend to reuse the same image over multiple CT's being created (Eg. in a script) but doing so will speed up execution for times you know your `*.tar.gz` is fine.

#### Prompt for password

> \[!TIP]
>
> From v1.1.1+, if you have `sshpass` installed (via `apt install sshpass`), you will be prompted
> for your SSH password, after which it'll use sshpass to authenticate. If `sshpass` is not found
> you will still be prompted by the ssh client for your password when it gets to that stage :-)

If you want to set a password but be prompted for it, append the `--prompt-password` switch that will request your password securely, avoiding the auto-generated password.

```
./proxmox-vm-to-ct.sh --source 192.168.0.152 \
                      --target the-matrix-reloaded \
                      --storage local-lvm \
                      --default-config \
                      --prompt-password
```
#### Ignore Prep'ing of VM

If you want to avoid [changes to the vm](#dietpi-changes) by the script, use the `--ignore-prep` switch.

```
./proxmox-vm-to-ct.sh --source 192.168.0.152 \
                      --target the-matrix-reloaded \
                      --storage local-lvm \
                      --default-config \
                      --ignore-prep
```

#### Containerd VM to CT

The [default CT configuration](#default-configuration) is not designed for VMs that have a containerd (Docker/Podman) engine installed. If your VM has Docker or Podman installed, converting to a CT will generate errors as described in [ISSUE: Failed to Create CT](https://github.com/thushan/proxmox-vm-to-ct/issues/2#issuecomment-1898335593).

You can create a privilleged container with additional features required by using the `--default-config-containerd` (or `--default-config-docker`):

```
./proxmox-vm-to-ct.sh --source 192.168.0.152 \
                      --target the-matrix-reloaded \
                      --storage local-lvm \
                      --default-config-docker
```

See what's included with [default containerd](#default-configuration---containerd--docker--podman) for more information.

## Usage
```
Usage: proxmox-vm-to-ct.sh --storage <name> --source <hostname|file> --target <name> [options]

Options:
  --storage <name>
      Name of the Proxmox Storage container (Eg. local-zfs, local-lvm, etc)
  --source <hostname> | <file: *.tar.gz>
      Source VM to convert to CT (Eg. postgres-vm.fritz.box or 192.168.0.10, source-vm.tar.gz file locally)
  --source-user <username>
      Source VM's SSH username to connect with. (Eg. root)
  --source-port <port>
      Source VM's SSH port to connect to. (Eg. 22)
  --source-output <path>, --output <path>, -o <path>
      Location of the source VM output (default: /tmp/proxmox-vm-to-ct/<hostname>.tar.gz)
  --target <name>
      Name of the container to create (Eg. postgres-ct)
  --target-config <path>
      Path to target configuration, for an example see default-config.env
  --default-config
      Default configuration for container (2 CPU, 2GB RAM, 20GB Disk)
  --default-config-containerd, --default-config-docker
      Default configuration for containerd containers (default + privileged, features: nesting, keyctl)
  --ignore-prep
      Ignore modifying the VM before snapshotting
  --ignore-dietpi
      Ignore DietPi specific modifications on the VM before snapshotting. (ignored with --ignore-prep)
  --prompt-password
      Prompt for a password for the container, temporary one generated & displayed otherwise
  --help
      Display this help message
```

### Default Configuration

Switch: `--default-config`

The default Container settings (stored in `CT_DEFAULT_*` vars) that are activated with the switch `--default-config` are:

<table>
  <tr>
    <th align="right">CPU</th>
    <td>2 Cores</td>
  </tr>
  <tr>
    <th align="right">RAM</th>
    <td>2048MB</td>
  </tr>
  <tr>
    <th align="right">HDD</th>
    <td>20GB</td>
  </tr>
  <tr>
    <th align="right">NET</th>
    <td><code>name=eth0,ip=dhcp,ip6=auto,bridge=vmbr0,firewall=1</code></td>
  </tr>
  <tr>
    <th align="right">ARCH</th>
    <td>amd64</td>
  </tr>
  <tr>
    <th align="right">OSTYPE</th>
    <td>debian</td>
  </tr>
  <tr>
    <th align="right">ONBOOT</th>
    <td><code>false</code></td>
  </tr>
  <tr>
    <th align="right">FEATURES</th>
    <td><code>nesting</code></td>
  </tr>
  <tr>
    <th align="right">UNPRIVILEGED</th>
    <td><code>true</code></td>
  </tr>
</table>

At this time, you'll have to modify the file to change that configuration - but will be implemented soon via commandline.

### Default Configuration - containerd / Docker / Podman

Switch: `--default-config-containerd`, `--default-config-docker`

For VM's that have a `containerd` instance (or Docker, Podman etc) we need a few more defaults. So in addition to the [default configuration](#default-configuration), this switch enables:

<table>
  <tr>
    <th align="right">FEATURES</th>
    <td><code>nesting</code>, <code>keyctl</code></td>
  </tr>
  <tr>
    <th align="right">UNPRIVILEGED</th>
    <td><em><code>false</code></em></td>
  </tr>
</table>

### DietPi Changes

> \[!NOTE]
> Changes are only made if we detect a DietPi installation by checking for
> `/boot/dietpi/.version` file.

The script prep's a DietPi (6.x | 7.x | 8.x or 9.x release) by making the following changes:

* Sets the `.dietpi_hw_model_identifier` from `21` (`x86_64`) to `75` (`container`) as per [documentation](https://github.com/MichaIng/DietPi/blob/master/dietpi/func/dietpi-obtain_hw_model#L27)
* Sets up first-login install sequence (even if you've done it already) so each container gets updates and updating of passwords instead of any randomly generated ones from the script by modifying `/boot/dietpi/.install_stage`.
* Stops DietPi-CloudShell which is CloudHell when you reboot as a container in Proxmox otherwise.
* Adds the purging of `grub-pc tiny-initramfs linux-image-amd64` packages which aren't required as a container - see [Michalng's comment](https://dietpi.com/blog/?p=2642#comment-5808).

The changes are found in the `vm_ct_prep` function (a snapshot can be found [here](https://github.com/thushan/proxmox-vm-to-ct/blob/198a7516c04c044ed90645864643677004884586/proxmox-vm-to-ct.sh#L395).)

You can skip these for non-DietPi images with `--ignore-dietpi` or overall `--ignore-prep` switches, but are ignored if no DietPi image is detected (say it's a stock debian VM).

### Grub Boot, OMG WHAT?

OMG, what the heck is this?

![Grub Prune](artefacts/intro-proxmox-ct-grub.png)

Don't worry, your DietPi image doesn't need `grub-pc,m tiny-initramfs & linux-image-amd64` packages, so they were removed and it's asking whether to remove them from Grub. You can say `YES` - see [Michalng's comment](https://dietpi.com/blog/?p=2642#comment-5808).

# Issues, Comments, Improvements

Always welcome contributions, feedback or revisions! Fork the repository and PR back :-)

# Acknowledgements

This script was created with the help of the following folks:

* [@y5t3ry/machine-to-proxmox-lxc-ct-converter](https://github.com/my5t3ry/machine-to-proxmox-lxc-ct-converter) by Sascha Basts
* [DietPi Blog: DietPi LXC containers in Proxmox](https://dietpi.com/blog/?p=2642) by StephenStS

And references:

* [Proxmox: `pct` documentation](https://pve.proxmox.com/pve-docs/pct.1.html)
* [DietPi: HW Models](https://github.com/MichaIng/DietPi/blob/master/dietpi/func/dietpi-obtain_hw_model)
* [@dazen/proxmox-dietpi-installer](https://github.com/dazeb/proxmox-dietpi-installer)
