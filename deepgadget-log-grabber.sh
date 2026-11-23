#!/bin/bash

# This script is intended to run on a Manycore machine and collects various system logs and information for diagnostic purposes.
# It includes the use of NVIDIA's bug report script to gather detailed information about NVIDIA GPUs and other system info.
# Credit to NVIDIA Corporation for the nvidia-bug-report.sh script.
# Note: This script consolidates system information, which may include sensitive data. User discretion advised.

# Copyright 2024 Manycore, Inc.
# Author(s):		Jiseo Choi
# Script License:	BSD 3-clause

# Script info and disclaimer
script_info_and_disclaimer() {
    echo "Usage: $(basename "$0") [--short] [--detail] [output-name]"
    echo "  --short:      Collect only /etc config and /var/log entries (faster)."
    echo "  --detail:     Also collect all files under /etc and archived (rotated) logs under /var/log."
    echo "  output-name:  Optional. Archive will be saved as <output-name>.tar.gz (default: Manycore-bug-report.tar.gz)"
    echo "                Example: $(basename "$0") deepgadget-A100-5  ->  deepgadget-A100-5.tar.gz"
    echo
    echo "This script is intended to run on a Manycore machine and collects various system logs and information for diagnostic purposes."
    echo "Supported OS: Debian/Ubuntu (apt) and RHEL-compatible distributions such as Rocky Linux, CentOS, AlmaLinux (dnf/yum)."
    echo "Detected package manager: ${PKG_MGR:-none}"
    echo "It includes the use of NVIDIA's bug report script to gather detailed information about NVIDIA GPUs and other system info."
    echo "Credit to NVIDIA Corporation for the nvidia-bug-report.sh script."
    echo
    echo "This script will, optionally, attempt to install any missing packages required for collecting system information."
    echo "This script may install the following, dependent on them being useful based on the detected target system:"
    CURRENT_TOOL=0
    while [ ${CURRENT_TOOL} -lt ${#NEEDED_TOOLS[@]} ]; do
        set -- $(echo ${NEEDED_TOOLS[${CURRENT_TOOL}]} | tr -d ',')
        echo " * $(pkg_name "${2}")"
        CURRENT_TOOL=$((${CURRENT_TOOL}+1))
    done | sort
    confirm_tools
    echo
    echo "By delivering '${OUTPUT_NAME}.tar.gz' to Manycore, you acknowledge"
    echo "and agree that sensitive information may inadvertently be included in"
    echo "the output. Notwithstanding the foregoing, Manycore will use the"
    echo "output only for the purpose of investigating your reported issue."
    echo
    if [ $DETAIL_MODE -eq 1 ]; then
        echo "WARNING: --detail mode is enabled. The following sensitive data categories"
        echo "may be included in the archive:"
        echo "  * All files under /etc (known credential files are excluded; see below)"
        echo "  * Archived (rotated) log files from /var/log (.gz/.bz2/.xz/.zst, and -YYYYMMDD on RHEL)"
        echo
        echo "The following files and directories are explicitly excluded from /etc:"
        echo "  * shadow, shadow-, gshadow, gshadow-  (password hashes)"
        echo "  * ssh_host_*_key                      (SSH host private keys)"
        echo "  * /etc/ssl/private/                   (SSL/TLS private keys)"
        echo "  * /etc/kubernetes/                    (Kubernetes credentials)"
        echo "  * /etc/credstore/, /etc/credstore.encrypted/"
        echo "  * /etc/NetworkManager/system-connections/ (saved Wi-Fi/VPN credentials)"
        echo "  * /etc/sysconfig/network-scripts/keys-*  (saved Wi-Fi/802.1x credentials)"
        echo
        echo "Review the archive carefully before sharing it with Manycore support."
        echo
    fi
}

confirm_tools() {
    if [[ -v SKIP_TOOLS ]]; then
        # The user (or --short) has already decided non-interactively, so no need to prompt.
        # SKIP_TOOLS=0 installs missing tools; any other value skips installation.
        [[ "$SKIP_TOOLS" == "0" ]] || SKIP_TOOLS=1
        return
    fi

    echo "You may set SKIP_TOOLS=0 (install) or SKIP_TOOLS=1 (skip) to answer the following prompt automatically."
    echo "  Example: sudo SKIP_TOOLS=0 bash $(basename "$0")"
    read -N 1 -p "Press Y to install these tools, press any other key to continue without them. " CONFIRM_TOOLS < /dev/tty
    echo
    if [[ "${CONFIRM_TOOLS,,}" == "y" ]]; then
        SKIP_TOOLS=0
    else
        SKIP_TOOLS=1
    fi
}

integer_check() {
    if [[ ! "${1}" =~ ^-?[0-9]+$ ]]; then
        echo 0
        return
    fi

    echo 1
    return
}

# Write a notice into a collected file when it ended up empty (tool missing or no data).
# Usage: note_if_empty <file> <description>
note_if_empty() {
    if [ ! -s "${1}" ]; then
        echo "No ${2} data available. The command may not exist or returned no output on this machine." >"${1}"
    fi
}

# Run nvidia-smi only when it exists, so a missing driver does not leave "command not found" in the output.
# Usage: run_nvidia_smi <output-file> [nvidia-smi arguments...]
run_nvidia_smi() {
    local out="${1}"; shift
    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi "$@" >"${out}" 2>&1
    fi
    note_if_empty "${out}" "nvidia-smi"
}

# Parse arguments: [--short] [--detail] [output-name]
# --short:  collect only /etc config and /var/log entries (faster)
# --detail: also collect all files under /etc and archived logs under /var/log
SHORT_MODE=0
DETAIL_MODE=0
OUTPUT_NAME="Manycore-bug-report"
for _arg in "$@"; do
    case "$_arg" in
        --short) SHORT_MODE=1 ;;
        --detail) DETAIL_MODE=1 ;;
        --*) ;;
        *) OUTPUT_NAME="$_arg" ;;
    esac
done
unset _arg
# In short mode no external tools are needed; suppress the install prompt
[ $SHORT_MODE -eq 1 ] && SKIP_TOOLS=1

# Minimal RHEL/CentOS installs and container images may not ship sudo.
# When already running as root, run "sudo" commands directly; otherwise sudo is required.
if ! command -v sudo >/dev/null 2>&1; then
    if [ "$(id -u)" -eq 0 ]; then
        sudo() { "$@"; }
    else
        echo "sudo is not installed. Please run this script as root: bash $(basename "$0") $*"
        exit 1
    fi
fi

# We will later check whether this machine will benefit from certain tools, rather than just installing them.
# Proactively assume the machine is not a VM
IS_VIRTUAL_MACHINE=0

check_if_virtualized() {
    SYSTEM_MANUFACTURER="$(sudo dmidecode | grep -A1 "System Information" | grep "Manufacturer" | sed 's/^\tManufacturer: //')"
    if [[ "${SYSTEM_MANUFACTURER}" == "QEMU" ]]; then
        IS_VIRTUAL_MACHINE=1
    else
        IS_VIRTUAL_MACHINE=0
    fi
}

# Detect the OS family from the available package manager.
#   PKG_FAMILY: debian | rhel | unknown
#   PKG_MGR:    apt-get | dnf | yum | (empty)
if command -v apt-get >/dev/null 2>&1; then
    PKG_FAMILY="debian"; PKG_MGR="apt-get"
elif command -v dnf >/dev/null 2>&1; then
    PKG_FAMILY="rhel"; PKG_MGR="dnf"
elif command -v yum >/dev/null 2>&1; then
    PKG_FAMILY="rhel"; PKG_MGR="yum"
else
    PKG_FAMILY="unknown"; PKG_MGR=""
fi

# Translate a Debian package name to the package name used on this OS.
pkg_name() {
    if [ "$PKG_FAMILY" = "rhel" ]; then
        case "${1}" in
            lm-sensors) echo "lm_sensors"; return ;;
        esac
    fi
    echo "${1}"
}

# List the tools to install and any tool metadata
# Usage:
#    1: executable to check for,
#    2: package name,
#    3: executable check status of 2 (0 = fail, 1 = success, 2 = unchecked)
#    4: tool is useful for VMs (0 = no, 1 = yes)
# This array should not be modified after set, except through the update_needed_tools function.
declare -a NEEDED_TOOLS
NEEDED_TOOLS=(
    "smartctl, smartmontools, 2, 0",
    "ipmitool, ipmitool, 2, 0",
    "sensors, lm-sensors, 2, 0",
    "iostat, sysstat, 2, 1",
    "lshw, lshw, 2, 1"
)

update_needed_tools() {
    # Update a field in the NEEDED_TOOLS array
    # Usage:
    #    1: index of tool in array
    #    2: argument to update
    #    3: new value for argument
    # Example changing the status of an executable check:
    #    update_needed_tools 0 3 1

    # Verify the index and argument supplied are integers or exit.
    if [[ ! $(integer_check "${1}") -eq 1 || ! $(integer_check "${2}") -eq 1 ]]; then
        echo "An index or argument supplied in update_needed_tools was not an integer."
        echo "Please report this issue to Manycore support for review."
        exit 1
    fi

    NEEDED_TOOLS[${1}]="$(echo ${NEEDED_TOOLS[${1}]} | awk -F ', ' -v OFS=', ' "{ \$${2}="${3}"; print }")"
}

validate_tools_array() {
    # Ensure the tools array looks sensible, based on the structural rules.
    CURRENT_TOOL=0
    while [ ${CURRENT_TOOL} -lt ${#NEEDED_TOOLS[@]} ]; do
        set -- $(echo ${NEEDED_TOOLS[${CURRENT_TOOL}]} | tr -d ',')

    if [[ ! $(integer_check "${3}") -eq 1 || ! $(integer_check "${4}") -eq 1 ]]; then
        echo "An executable check status or VM tool value supplied in NEEDED_TOOLS was not an integer."
        echo "Please report this issue to Manycore support for review."
        exit 1
    fi

        CURRENT_TOOL=$((${CURRENT_TOOL}+1))
    done
}

check_needed_tools() {
    if [ $SKIP_TOOLS -eq 0 ] && [ -z "$PKG_MGR" ]; then
        echo "No supported package manager (apt-get/dnf/yum) found. Continuing without installing tools."
        SKIP_TOOLS=1
    fi

    if [ $SKIP_TOOLS -eq 0 ]; then
        case "$PKG_MGR" in
            apt-get) sudo apt-get update >/dev/null 2>&1 ;;
            dnf)     sudo dnf -y makecache >/dev/null 2>&1 ;;
            yum)     sudo yum -y makecache fast >/dev/null 2>&1 ;;
        esac
    fi

    CURRENT_TOOL=0
    while [ ${CURRENT_TOOL} -lt ${#NEEDED_TOOLS[@]} ]; do
        # Bash does not have multidimensional arrays, but it's possible to make do in a way that is reasonably easy to read.
        set -- $(echo ${NEEDED_TOOLS[${CURRENT_TOOL}]} | tr -d ',')

        # Proactively assume a tool is not beneficial on a VM
        IS_VM_TOOL=${4:-0}

        if ! command -v ${1} >/dev/null 2>&1; then
            update_needed_tools ${CURRENT_TOOL} 3 0
        else
            update_needed_tools ${CURRENT_TOOL} 3 1
            # The tool is already available, no need to proceed further with this iteration of the loop.
            CURRENT_TOOL=$((${CURRENT_TOOL}+1))
            continue
        fi

        if [ $SKIP_TOOLS -eq 1 ]; then
            # The script has been told not to install tools, no need to proceed further with this iteration of the loop.
            CURRENT_TOOL=$((${CURRENT_TOOL}+1))
            continue
        fi

        if [[ $IS_VIRTUAL_MACHINE -eq 1 && $IS_VM_TOOL -eq 0 ]]; then
            # The tool is not beneficial for a VM, no need to proceed further with this iteration of the loop.
            CURRENT_TOOL=$((${CURRENT_TOOL}+1))
            continue
        fi

        PKG="$(pkg_name "${2}")"
        echo "Installing ${PKG}"
        sudo "$PKG_MGR" install -y "${PKG}" >/dev/null 2>&1
        if ! command -v ${1} >/dev/null 2>&1; then
            echo "  Could not install ${PKG} (not available in the configured repositories). Continuing without ${1}."
        fi

        CURRENT_TOOL=$((${CURRENT_TOOL}+1))
    done
}

script_info_and_disclaimer

check_if_virtualized

validate_tools_array

check_needed_tools

# Define and create temporary directory
TMP_DIR="tmp_Manycore_bug_report"
mkdir -p "$TMP_DIR"

# Define and create main directory for logs
FINAL_DIR="$TMP_DIR/$OUTPUT_NAME"
mkdir -p "$FINAL_DIR"

# Directories under Manycore-bug-report
DRIVES_AND_STORAGE_DIR="$FINAL_DIR/drives-and-storage"
mkdir -p "$DRIVES_AND_STORAGE_DIR"
SYSTEM_LOGS_DIR="$FINAL_DIR/system-logs"
mkdir -p "$SYSTEM_LOGS_DIR"
REPOS_AND_PACKAGES_DIR="$FINAL_DIR/repos-and-packages"
mkdir -p "$REPOS_AND_PACKAGES_DIR"
NETWORKING_DIR="$FINAL_DIR/networking"
mkdir -p "$NETWORKING_DIR"
GPU_MEMORY_ERRORS_DIR="$FINAL_DIR/gpu-memory-errors"
mkdir -p "$GPU_MEMORY_ERRORS_DIR"
BMC_INFO_DIR="$FINAL_DIR/bmc-info"
mkdir -p "$BMC_INFO_DIR"
GRUB_DIR="$FINAL_DIR/grub"
mkdir -p "$GRUB_DIR"
ETC_CONFIG_DIR="$FINAL_DIR/etc-config"
mkdir -p "$ETC_CONFIG_DIR"
ETC_SERVICES_DIR="$ETC_CONFIG_DIR/services"
mkdir -p "$ETC_SERVICES_DIR"
ETC_MODULES_DIR="$ETC_CONFIG_DIR/modules"
mkdir -p "$ETC_MODULES_DIR"

if [ $DETAIL_MODE -eq 1 ]; then
    ETC_SNAPSHOT_DIR="$FINAL_DIR/etc-snapshot"
    mkdir -p "$ETC_SNAPSHOT_DIR"
    VAR_LOG_ARCHIVED_DIR="$SYSTEM_LOGS_DIR/var-log-archived"
    mkdir -p "$VAR_LOG_ARCHIVED_DIR"
fi


# Collect SMART data for all drives
collect_drive_checks() {
    lsblk -o NAME,MAJ:MIN,RM,SIZE,RO,FSTYPE,LABEL,UUID,TYPE,MOUNTPOINT >"$DRIVES_AND_STORAGE_DIR/lsblk.txt"

    # Collect SMART data for all drives
    DRIVES=$(lsblk | grep -E "^sd|^nvm" | awk '{print $1}')
    if ! command -v smartctl >/dev/null 2>&1; then
        note_if_empty "$DRIVES_AND_STORAGE_DIR/smartctl.txt" "smartctl"
        return
    fi
    for DRIVE in ${DRIVES}; do
        sudo smartctl -x /dev/"${DRIVE}" >"$DRIVES_AND_STORAGE_DIR/smartctl-${DRIVE}.txt" 2>&1
    done
}

# Collect /etc networking, services, and modules configuration
collect_etc_config() {
    # --- Networking ---
    for f in /etc/hosts /etc/hostname /etc/resolv.conf /etc/nsswitch.conf \
              /etc/hosts.allow /etc/hosts.deny; do
        [ -f "$f" ] && cp "$f" "${NETWORKING_DIR}/etc-$(basename "$f" | tr '.' '-').txt" 2>/dev/null
    done

    if [ -f /etc/nftables.conf ]; then
        cp /etc/nftables.conf "${NETWORKING_DIR}/etc-nftables-conf.txt"
    fi

    # RHEL/Rocky/CentOS network configuration
    # ifcfg-* only; keys-* files hold Wi-Fi/802.1x secrets and are excluded
    if [ -d /etc/sysconfig/network-scripts ]; then
        mkdir -p "${NETWORKING_DIR}/sysconfig-network-scripts"
        find /etc/sysconfig/network-scripts -maxdepth 1 -type f -name "ifcfg-*" | sort | while read -r f; do
            cp "$f" "${NETWORKING_DIR}/sysconfig-network-scripts/" 2>/dev/null
        done
    fi
    [ -f /etc/sysconfig/network ] && cp /etc/sysconfig/network "${NETWORKING_DIR}/etc-sysconfig-network.txt" 2>/dev/null
    [ -f /etc/selinux/config ] && cp /etc/selinux/config "${ETC_CONFIG_DIR}/selinux-config.txt" 2>/dev/null

    if [ -d /etc/network ]; then
        find /etc/network -maxdepth 2 -type f | sort | while read -r f; do
            rel="${f#/etc/network/}"
            mkdir -p "${NETWORKING_DIR}/etc-network/$(dirname "$rel")"
            cp "$f" "${NETWORKING_DIR}/etc-network/$rel" 2>/dev/null
        done
    fi

    # NM main config only (system-connections excluded to avoid stored credentials)
    if [ -f /etc/NetworkManager/NetworkManager.conf ]; then
        cp /etc/NetworkManager/NetworkManager.conf "${NETWORKING_DIR}/etc-NetworkManager.conf.txt"
    fi

    if [ -d /etc/systemd/network ]; then
        find /etc/systemd/network -maxdepth 1 \
            \( -name "*.network" -o -name "*.netdev" -o -name "*.link" \) -type f | \
            sort | while read -r f; do
            cp "$f" "${NETWORKING_DIR}/" 2>/dev/null
        done
    fi

    # --- Services ---
    for conf in system.conf journald.conf logind.conf timesyncd.conf resolved.conf; do
        [ -f "/etc/systemd/$conf" ] && cp "/etc/systemd/$conf" "${ETC_SERVICES_DIR}/"
    done

    if [ -d /etc/systemd/system ]; then
        find /etc/systemd/system -maxdepth 1 \
            \( -name "*.service" -o -name "*.target" -o -name "*.timer" \
               -o -name "*.socket" -o -name "*.mount" \) 2>/dev/null | \
            sort >"${ETC_SERVICES_DIR}/systemd-system-units-list.txt"
        while IFS= read -r f; do
            [ -f "$f" ] && cp "$f" "${ETC_SERVICES_DIR}/" 2>/dev/null
        done <"${ETC_SERVICES_DIR}/systemd-system-units-list.txt"
    fi

    ls -la /etc/init.d/ >"${ETC_SERVICES_DIR}/init-d-list.txt" 2>/dev/null
    note_if_empty "${ETC_SERVICES_DIR}/init-d-list.txt" "/etc/init.d"

    [ -f /etc/crontab ] && cp /etc/crontab "${ETC_SERVICES_DIR}/crontab.txt"
    for crondir in /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly; do
        if [ -d "$crondir" ]; then
            tag="$(basename "$crondir")"
            ls -la "$crondir" >"${ETC_SERVICES_DIR}/${tag}-list.txt" 2>/dev/null
            for f in "$crondir"/*; do
                [ -f "$f" ] && cat "$f" >>"${ETC_SERVICES_DIR}/${tag}-contents.txt" 2>/dev/null
            done
        fi
    done

    # --- Modules ---
    [ -f /etc/modules ] && cp /etc/modules "${ETC_MODULES_DIR}/etc-modules.txt"

    if [ -d /etc/modules-load.d ]; then
        find /etc/modules-load.d -maxdepth 1 -type f | sort | while read -r f; do
            cp "$f" "${ETC_MODULES_DIR}/" 2>/dev/null
        done
    fi

    if [ -d /etc/modprobe.d ]; then
        find /etc/modprobe.d -maxdepth 1 -type f | sort | while read -r f; do
            cp "$f" "${ETC_MODULES_DIR}/" 2>/dev/null
        done
    fi

    # --- Slurm ---
    if [ -d /etc/slurm ]; then
        cp -r /etc/slurm "${ETC_CONFIG_DIR}/slurm" 2>/dev/null
    fi

    # --- Lustre ---
    if [ -d /etc/lustre ]; then
        cp -r /etc/lustre "${ETC_CONFIG_DIR}/lustre" 2>/dev/null
    fi
}

if [ $SHORT_MODE -eq 0 ]; then
    # Generate NVIDIA bug report
    echo "Running nvidia-bug-report.sh..."
    sudo nvidia-bug-report.sh >/dev/null 2>&1

    # If nvidia-bug-report.log.gz exists, decompress it
    if [ -f "nvidia-bug-report.log.gz" ]; then
        gunzip -c nvidia-bug-report.log.gz >"${FINAL_DIR}/nvidia-bug-report.log"
        sudo rm nvidia-bug-report.log.gz
    fi
fi

echo "Collecting system logs and information..."

# Collect system logs
#   Debian/Ubuntu: dmesg, kern.log, syslog, dpkg.log
#   RHEL/Rocky/CentOS: messages, boot.log, dnf.log, dnf.rpm.log, yum.log
for log in /var/log/dmesg /var/log/kern.log /var/log/syslog /var/log/dpkg.log \
           /var/log/messages /var/log/boot.log /var/log/dnf.log /var/log/dnf.rpm.log /var/log/yum.log; do
    if [ -f "$log" ]; then
        sudo cp "$log" "$SYSTEM_LOGS_DIR/"
    fi
done

# Collect all apt history logs into one sorted file (Debian/Ubuntu)
if [ -d /var/log/apt ]; then
    find /var/log/apt -type f -name "history.log*" | sort -Vr | while read log; do
        if [[ "$log" =~ \.gz$ ]]; then
            zcat "$log" | sudo tee -a "$SYSTEM_LOGS_DIR/apt-history.log" >/dev/null
        else
            cat "$log" | sudo tee -a "$SYSTEM_LOGS_DIR/apt-history.log" >/dev/null
        fi
    done
fi

# Collect dnf/yum transaction history (RHEL/Rocky/CentOS)
if [ "$PKG_FAMILY" = "rhel" ]; then
    sudo "$PKG_MGR" history list >"$SYSTEM_LOGS_DIR/${PKG_MGR}-history.txt" 2>/dev/null
    note_if_empty "$SYSTEM_LOGS_DIR/${PKG_MGR}-history.txt" "${PKG_MGR} history"
fi

# Collect Slurm and Lustre logs from /var/log if present
for _logdir in /var/log/slurm /var/log/lustre; do
    [ -d "$_logdir" ] && sudo cp -r "$_logdir" "${SYSTEM_LOGS_DIR}/" 2>/dev/null
done
unset _logdir

sudo dmesg -Tl err >"${SYSTEM_LOGS_DIR}/dmesg-errors.txt"

if [ $SHORT_MODE -eq 0 ]; then
    # Limit to last 30 days to avoid excessively large output; remove --since for full journal
    sudo journalctl --since "30 days ago" >"${SYSTEM_LOGS_DIR}/journalctl.txt"
fi

if [ $SHORT_MODE -eq 0 ]; then

ibstat >"${FINAL_DIR}/ibstat.txt" 2>/dev/null
if [ ! -s "${FINAL_DIR}/ibstat.txt" ]; then
    echo "No InfiniBand data available. This machine may not have InfiniBand." >"${FINAL_DIR}/ibstat.txt"
fi

sudo ipmitool sel elist >"${BMC_INFO_DIR}/ipmi-elist.txt" 2>/dev/null
if [ ! -s "${BMC_INFO_DIR}/ipmi-elist.txt" ]; then
    echo "No IPMI ELIST data available. This machine may not have IPMI." >"${BMC_INFO_DIR}/ipmi-elist.txt"
fi
sudo ipmitool sdr >"${BMC_INFO_DIR}/ipmi-sdr.txt" 2>/dev/null
if [ ! -s "${BMC_INFO_DIR}/ipmi-sdr.txt" ]; then
    echo "No IPMI SDR data available. This machine may not have IPMI." >"${BMC_INFO_DIR}/ipmi-sdr.txt"
fi

sensors >"${FINAL_DIR}/sensors.txt" 2>/dev/null
if [ ! -s "${FINAL_DIR}/sensors.txt" ]; then
    echo "No sensor data available. This machine may not have sensors." >"${FINAL_DIR}/sensors.txt"
fi

sudo iostat -xt >"${DRIVES_AND_STORAGE_DIR}/iostat.txt" 2>/dev/null
if [ ! -s "${DRIVES_AND_STORAGE_DIR}/iostat.txt" ]; then
    echo "No iostat data available. This machine may not have iostat." >"${DRIVES_AND_STORAGE_DIR}/iostat.txt"
fi

sudo lshw >"${FINAL_DIR}/hw-list.txt" 2>/dev/null
if [ ! -s "${FINAL_DIR}/hw-list.txt" ]; then
    echo "No lshw data available. This machine may not have lshw." >"${FINAL_DIR}/hw-list.txt"
fi

# Collect SW Raid info
if command -v mdadm >/dev/null 2>&1; then
    sudo mdadm --detail --scan >"${DRIVES_AND_STORAGE_DIR}/mdadm-scan.txt"
    # Debian/Ubuntu: /etc/mdadm/mdadm.conf, RHEL/Rocky/CentOS: /etc/mdadm.conf
    cat /etc/mdadm/mdadm.conf /etc/mdadm.conf >"${DRIVES_AND_STORAGE_DIR}/mdadm-conf.txt" 2>/dev/null
    note_if_empty "${DRIVES_AND_STORAGE_DIR}/mdadm-scan.txt" "mdadm scan"
    note_if_empty "${DRIVES_AND_STORAGE_DIR}/mdadm-conf.txt" "mdadm.conf"
fi

# Collecdt GRUB info
cat /proc/cmdline >"${GRUB_DIR}/proc_cmdline.txt"
cat /etc/default/grub >"${GRUB_DIR}/grub.txt" 2>/dev/null
note_if_empty "${GRUB_DIR}/grub.txt" "/etc/default/grub"
if command -v grubby >/dev/null 2>&1; then
    # RHEL/Rocky/CentOS: boot entries and per-kernel arguments
    sudo grubby --info=ALL >"${GRUB_DIR}/grubby.txt" 2>/dev/null
    note_if_empty "${GRUB_DIR}/grubby.txt" "grubby"
fi
if [ -d /etc/default/grub.d/ ]; then
    cp -r /etc/default/grub.d/ "${GRUB_DIR}/"
fi

# Check for memory remapping and memory errors on GPUs
run_nvidia_smi "${GPU_MEMORY_ERRORS_DIR}/remapped-memory.txt" \
    --query-remapped-rows=gpu_bus_id,gpu_uuid,remapped_rows.correctable,remapped_rows.uncorrectable,remapped_rows.pending,remapped_rows.failure \
    --format=csv

run_nvidia_smi "${GPU_MEMORY_ERRORS_DIR}/ecc-errors.txt" \
    --query-gpu=index,pci.bus_id,uuid,ecc.errors.corrected.volatile.dram,ecc.errors.corrected.volatile.sram \
    --format=csv

run_nvidia_smi "${GPU_MEMORY_ERRORS_DIR}/uncorrected-ecc_errors.txt" \
    --query-gpu=index,pci.bus_id,uuid,ecc.errors.uncorrected.aggregate.dram,ecc.errors.uncorrected.aggregate.sram \
    --format=csv

# Check hibernation settings
sudo systemctl status hibernate.target hybrid-sleep.target \
    suspend-then-hibernate.target sleep.target suspend.target >"${FINAL_DIR}/hibernation-settings.txt" 2>&1
note_if_empty "${FINAL_DIR}/hibernation-settings.txt" "systemctl hibernation target"

# Collect package repository info
if [ "$PKG_FAMILY" = "rhel" ]; then
    # RHEL/Rocky/CentOS: /etc/yum.repos.d/*.repo
    output_file="${REPOS_AND_PACKAGES_DIR}/yum-repos.txt"
    for file in /etc/yum.repos.d/*.repo; do
        if [ -f "$file" ]; then
            echo "$(basename "$file")" >>"$output_file"
            grep -v '^#' "$file" >>"$output_file"
            echo "" >>"$output_file"
        fi
    done
    note_if_empty "$output_file" "/etc/yum.repos.d"
    sudo "$PKG_MGR" repolist all >"${REPOS_AND_PACKAGES_DIR}/repolist.txt" 2>/dev/null
    note_if_empty "${REPOS_AND_PACKAGES_DIR}/repolist.txt" "${PKG_MGR} repolist"
else
    # Debian/Ubuntu: /etc/apt/sources.list.d/*
    output_file="${REPOS_AND_PACKAGES_DIR}/listd-repos.txt"
    for file in /etc/apt/sources.list.d/*; do
        if [ -f "$file" ]; then
            echo "$(basename "$file")" >>"$output_file"

            cat "$file" >>"$output_file"

            echo "" >>"$output_file"
        fi
    done
fi

# Collect other system information
df -hTP >"${DRIVES_AND_STORAGE_DIR}/df.txt" 2>/dev/null
cat /etc/fstab >"${DRIVES_AND_STORAGE_DIR}/fstab.txt" 2>/dev/null
cat /proc/mdstat >"${DRIVES_AND_STORAGE_DIR}/mdstat.txt" 2>/dev/null
lsmod >"${FINAL_DIR}/lsmod.txt" 2>/dev/null
if [ "$PKG_FAMILY" = "rhel" ]; then
    rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\t%{INSTALLTIME:date}\n' 2>/dev/null | sort >"${REPOS_AND_PACKAGES_DIR}/rpm.txt"
    note_if_empty "${REPOS_AND_PACKAGES_DIR}/rpm.txt" "rpm"
else
    dpkg -l >"${REPOS_AND_PACKAGES_DIR}/dpkg.txt" 2>/dev/null
    grep -v '^#' /etc/apt/sources.list >"${REPOS_AND_PACKAGES_DIR}/sources-list.txt" 2>/dev/null
    note_if_empty "${REPOS_AND_PACKAGES_DIR}/dpkg.txt" "dpkg"
    note_if_empty "${REPOS_AND_PACKAGES_DIR}/sources-list.txt" "/etc/apt/sources.list"
fi
export PIP_DISABLE_PIP_VERSION_CHECK=1
# pip may only be available as pip3 (RHEL/Rocky/CentOS)
PIP_CMD="$(command -v pip || command -v pip3)"
[ -n "$PIP_CMD" ] && "$PIP_CMD" -v list >"${REPOS_AND_PACKAGES_DIR}/pip-list.txt" 2>/dev/null
unset PIP_DISABLE_PIP_VERSION_CHECK PIP_CMD
cat /proc/mounts >"${DRIVES_AND_STORAGE_DIR}/mounts.txt" 2>/dev/null
sudo sysctl -a >"${FINAL_DIR}/sysctl-all.txt" 2>/dev/null
systemctl --type=service >"${FINAL_DIR}/systemctl-services.txt" 2>/dev/null
if command -v netplan >/dev/null 2>&1; then
    sudo netplan get all >"${NETWORKING_DIR}/netplan.txt" 2>/dev/null
    note_if_empty "${NETWORKING_DIR}/netplan.txt" "netplan"
fi
if command -v nmcli >/dev/null 2>&1; then
    # Connection names and states only; secrets are not shown without --show-secrets
    { echo "## nmcli general"; nmcli general 2>&1
      echo; echo "## nmcli device status"; nmcli device status 2>&1
      echo; echo "## nmcli connection show"; nmcli connection show 2>&1; } >"${NETWORKING_DIR}/nmcli.txt"
fi
ip addr >"${NETWORKING_DIR}/ip-addr.txt" 2>/dev/null
sudo iptables -L --line-numbers >"${NETWORKING_DIR}/iptables.txt" 2>/dev/null
if command -v ufw >/dev/null 2>&1; then
    sudo ufw status >"${NETWORKING_DIR}/ufw-status.txt" 2>/dev/null
    note_if_empty "${NETWORKING_DIR}/ufw-status.txt" "ufw"
fi
if command -v firewall-cmd >/dev/null 2>&1; then
    # RHEL/Rocky/CentOS default firewall
    { echo "state: $(sudo firewall-cmd --state 2>&1)"; sudo firewall-cmd --list-all-zones 2>&1; } >"${NETWORKING_DIR}/firewalld.txt"
fi
if command -v nft >/dev/null 2>&1; then
    sudo nft list ruleset >"${NETWORKING_DIR}/nft-ruleset.txt" 2>/dev/null
    note_if_empty "${NETWORKING_DIR}/nft-ruleset.txt" "nft ruleset"
fi
if command -v sestatus >/dev/null 2>&1; then
    # SELinux mode (RHEL/Rocky/CentOS)
    sestatus >"${FINAL_DIR}/selinux-status.txt" 2>&1
fi
sudo resolvectl status >"${NETWORKING_DIR}/resolvectl-status.txt" 2>/dev/null
top -n 1 -b >"${FINAL_DIR}/top.txt" 2>/dev/null
note_if_empty "${DRIVES_AND_STORAGE_DIR}/df.txt" "df"
note_if_empty "${DRIVES_AND_STORAGE_DIR}/fstab.txt" "/etc/fstab"
note_if_empty "${DRIVES_AND_STORAGE_DIR}/mdstat.txt" "/proc/mdstat"
note_if_empty "${FINAL_DIR}/lsmod.txt" "lsmod"
note_if_empty "${REPOS_AND_PACKAGES_DIR}/pip-list.txt" "pip"
note_if_empty "${DRIVES_AND_STORAGE_DIR}/mounts.txt" "/proc/mounts"
note_if_empty "${FINAL_DIR}/sysctl-all.txt" "sysctl"
note_if_empty "${FINAL_DIR}/systemctl-services.txt" "systemctl"
note_if_empty "${NETWORKING_DIR}/ip-addr.txt" "ip addr"
note_if_empty "${NETWORKING_DIR}/iptables.txt" "iptables"
note_if_empty "${NETWORKING_DIR}/resolvectl-status.txt" "resolvectl"
note_if_empty "${FINAL_DIR}/top.txt" "top"
run_nvidia_smi "${FINAL_DIR}/nvidia-smi.txt"
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi -q 2>/dev/null | grep -E "Serial Number|Bus Id" >"${FINAL_DIR}/gpu-serials.txt"
fi
note_if_empty "${FINAL_DIR}/gpu-serials.txt" "nvidia-smi"
sudo ss --tcp --udp --listening --numeric --process >"${NETWORKING_DIR}/ss.txt" 2>/dev/null
note_if_empty "${NETWORKING_DIR}/ss.txt" "ss"
echo "$(uptime -p)" since "$(uptime -s)" >"${FINAL_DIR}/uptime.txt"

collect_drive_checks

fi # SHORT_MODE -eq 0

echo "Collecting /etc networking, services, and modules configuration..."
collect_etc_config

if [ $DETAIL_MODE -eq 1 ]; then
    echo "Collecting /etc contents (excluding sensitive files)..."
    FIND_ETC_ARGS=(
        -type f
        -not -name "shadow"
        -not -name "shadow-"
        -not -name "gshadow"
        -not -name "gshadow-"
        -not -name "ssh_host_*_key"
        -not -path "/etc/sysconfig/network-scripts/keys-*"
    )
    for sensitive_dir in "/etc/ssl/private" "/etc/kubernetes" "/etc/credstore" "/etc/credstore.encrypted" \
                         "/etc/NetworkManager/system-connections"; do
        FIND_ETC_ARGS+=(-not -path "${sensitive_dir}/*")
    done
    sudo find /etc "${FIND_ETC_ARGS[@]}" -print0 | while IFS= read -r -d '' src; do
        rel="${src#/etc/}"
        dest_dir="$ETC_SNAPSHOT_DIR/$(dirname "$rel")"
        sudo mkdir -p "$dest_dir"
        sudo cp "$src" "$dest_dir/"
    done

    echo "Estimating size of archived logs in /var/log..."
    VAR_LOG_ARCHIVE_SIZE=$(sudo find /var/log -type f \( -name "*.gz" -o -name "*.bz2" -o -name "*.xz" -o -name "*.zst" \
        -o -name "*-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]" \) -print0 \
        | sudo xargs -0 du -ch 2>/dev/null | tail -1 | awk '{print $1}')
    echo "  Archived logs total size: ${VAR_LOG_ARCHIVE_SIZE:-0}. Proceeding with collection..."

    echo "Collecting archived logs from /var/log..."
    sudo find /var/log -type f \( -name "*.gz" -o -name "*.bz2" -o -name "*.xz" -o -name "*.zst" \
        -o -name "*-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]" \) -print0 \
        | while IFS= read -r -d '' logfile; do
            rel_path="${logfile#/var/log/}"
            dest_dir="$VAR_LOG_ARCHIVED_DIR/$(dirname "$rel_path")"
            mkdir -p "$dest_dir"
            sudo cp "$logfile" "$dest_dir/"
        done
fi

# Compress all collected logs into a single file
if ! sudo tar -zcf "${OUTPUT_NAME}.tar.gz" -C "$TMP_DIR" "$OUTPUT_NAME"; then
    echo
    echo "ERROR: Failed to create ${OUTPUT_NAME}.tar.gz."
    echo "The collected files were kept in ${TMP_DIR}/${OUTPUT_NAME}."
    exit 1
fi

# Cleanup
sudo rm -rf "$TMP_DIR"

echo
echo "All logs have been collected and compressed into ${OUTPUT_NAME}.tar.gz."
echo
