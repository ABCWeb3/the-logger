#!/usr/bin/env bash
set -Eeuo pipefail

# Fully automatic Windows 11 IoT Enterprise LTSC 2024 Evaluation VM installer
# for Proxmox VE. Downloads the ISO directly from Microsoft's official redirect.

NAME="${NAME:-Win11-IoT-LTSC}"
RAM="${RAM:-2048}"
CORES="${CORES:-2}"
DISK_GB="${DISK_GB:-32}"
BRIDGE="${BRIDGE:-vmbr0}"
STORAGE="${STORAGE:-local-lvm}"

MS_URL="https://go.microsoft.com/fwlink/?clcid=0x409&country=us&culture=en-us&linkid=2270353"
ISO_NAME="win11-iot-enterprise-ltsc-2024-eval-x64.iso"
ISO_PATH="/var/lib/vz/template/iso/${ISO_NAME}"
ISO_VOL="local:iso/${ISO_NAME}"
VIRTIO_PATH="/var/lib/vz/template/iso/virtio-win.iso"
VIRTIO_VOL="local:iso/virtio-win.iso"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

echo "=================================================="
echo " Windows 11 IoT Enterprise LTSC 2024 - Proxmox"
echo "=================================================="

[[ $EUID -eq 0 ]] || die "Run this script as root."
command -v qm >/dev/null 2>&1 || die "Run this on the Proxmox host, not inside an LXC/VM."
command -v pvesm >/dev/null 2>&1 || die "pvesm not found."
command -v pvesh >/dev/null 2>&1 || die "pvesh not found."

# Pick VM storage automatically if local-lvm is unavailable.
if ! pvesm status | awk -v s="$STORAGE" 'NR>1 && $1==s && $3=="active"{ok=1} END{exit !ok}'; then
  STORAGE="$(pvesm status | awk 'NR>1 && $3=="active" && $1!="local" {print $1; exit}')"
fi
[[ -n "$STORAGE" ]] || die "No active VM storage found. Set STORAGE=your-storage and run again."

# Ensure default local ISO storage exists.
mkdir -p /var/lib/vz/template/iso

# Download official Windows ISO if needed.
if [[ ! -s "$ISO_PATH" ]]; then
  echo
  echo "Downloading Windows 11 IoT Enterprise LTSC 2024 Evaluation from Microsoft..."
  echo "This is several GB and may take some time depending on your connection."
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 5 --retry-delay 3 --progress-bar "$MS_URL" -o "$ISO_PATH"
  elif command -v wget >/dev/null 2>&1; then
    wget --content-disposition --show-progress -O "$ISO_PATH" "$MS_URL"
  else
    die "Neither curl nor wget is installed."
  fi
fi
[[ -s "$ISO_PATH" ]] || die "Windows ISO download failed."

# Download VirtIO drivers if needed.
if [[ ! -s "$VIRTIO_PATH" ]]; then
  echo
  echo "Downloading VirtIO Windows drivers..."
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 5 --retry-delay 3 --progress-bar \
      "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso" \
      -o "$VIRTIO_PATH"
  else
    wget --show-progress -O "$VIRTIO_PATH" \
      "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
  fi
fi
[[ -s "$VIRTIO_PATH" ]] || die "VirtIO ISO download failed."

VMID="${VMID:-$(pvesh get /cluster/nextid)}"

if qm status "$VMID" >/dev/null 2>&1; then
  die "VMID $VMID already exists."
fi

echo
echo "Creating VM with:"
echo "  VMID    : $VMID"
echo "  Name    : $NAME"
echo "  RAM     : ${RAM} MB"
echo "  CPU     : ${CORES} cores"
echo "  Disk    : ${DISK_GB} GB"
echo "  Storage : $STORAGE"
echo

qm create "$VMID" \
  --name "$NAME" \
  --ostype win11 \
  --machine q35 \
  --bios ovmf \
  --cpu host \
  --sockets 1 \
  --cores "$CORES" \
  --memory "$RAM" \
  --balloon 0 \
  --scsihw virtio-scsi-single \
  --agent enabled=1 \
  --net0 "virtio,bridge=$BRIDGE"

qm set "$VMID" --efidisk0 "$STORAGE:1,efitype=4m,pre-enrolled-keys=1"
qm set "$VMID" --tpmstate0 "$STORAGE:1,version=v2.0"
qm set "$VMID" --scsi0 "$STORAGE:$DISK_GB,discard=on,iothread=1,ssd=1"
qm set "$VMID" --ide2 "$ISO_VOL,media=cdrom"
qm set "$VMID" --ide0 "$VIRTIO_VOL,media=cdrom"
qm set "$VMID" --boot "order=ide2;scsi0"
qm set "$VMID" --vga std

qm start "$VMID"

echo
echo "=================================================="
echo " VM created and started successfully"
echo "=================================================="
echo "VMID: $VMID"
echo
echo "Open: Proxmox -> VM $VMID -> Console"
echo
echo "If Windows Setup does not see the disk:"
echo "  Load driver -> VirtIO CD -> vioscsi -> w11 -> amd64"
echo
echo "After Windows is installed, run from the VirtIO CD:"
echo "  virtio-win-guest-tools.exe"
