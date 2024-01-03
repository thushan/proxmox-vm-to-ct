# Proxmox DietPi VM to Container

This repository contains scripts and helpers to convert your Proxmox VM's to containers - with a special emphasis on DietPi VMs.

Yes, you can hardly contain yourself with excitement!

## Process

1. Install your 'base' image as a VM (be it DietPi or Debian etc.) on Proxmox as normal.
   * Configure the VM with the core tools you'd like.
     * Eg. Tools `vim`, `tmux` etc.
     * Eg. Settings region, network, wifi etc.
   * Look in the `~/vm` folder if there's a vm-prep script for your operating system to prepare it to be containerised. See below for more details.
   * Run the VM Preparation Script to prepare the base VM.
2. Run the `proxmox-vm-to-ct.sh` script (described below) to create a Container image with the relevant configuration
3. Start your fancy new containerised VM!

## Creating your Base VM

Create a Proxmox VM with any configuration you like for your base - so 2-cores, 1GB RAM, 8GB disk for example, but your real container may be 16-core, 32GB RAM, 320GB Disk. This base image configuration will not affect your future Containers - we'll configure thoses things in the script!

## VM Prep Scripts

Scripts found in `~/vm` folder contains scripts to help prepare a chosen distribution for containerisation. It's completely optional to run them.

* [DietPi](./vm/dietpi-prep.md) - Supports DietPi v8+

## Proxmox VM To CT

