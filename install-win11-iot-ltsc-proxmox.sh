#!/usr/bin/env bash
set -Eeuo pipefail

# Windows 11 IoT Enterprise LTSC 2024 Evaluation VM installer for Proxmox VE.
# Downloads Windows from Microsoft. Tries VirtIO first and automatically
# falls back to SATA + E1000 if the VirtIO host cannot be reached.

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
VIRTIO_URL="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
VIRTIO_PATH="/var/lib/vz/template/iso/virtio-win.iso"
VIRTIO_VOL="local:iso/virtio-win.iso"

die() { echo "ERROR: $*" >&2; exit 1; }

echo "=================================================="
echo " Windows 11 IoT Enterprise LTSC 2024 - Proxmox"
echo "=================================================="

[[ $EUID -eq 0 ]] || die "Run this script as root."
command -v qm >/dev/null 2>&1 || die "Run this on the Proxmox host, not inside an LXC/VM."
command -v pvesm >/dev/null 2>&1 || die "pvesm not found."
command -v pvesh >/dev/null 2>&1 || die "pvesh not found."

if ! pvesm status | awk -v s="$STORAGE" 'NR>1 && $1==s && $3=="active"{ok=1} END{exit !ok}'; then
  STORAGE="$(pvesm status | awk 'NR>1 && $3=="active" && $1!="local" {print $1; exit}')"
fi
[[ -n "$STORAGE" ]] || die "No active VM storage found. Set STORAGE=your-storage and run again."

mkdir -p /var/lib/vz/template/iso

# Download official Windows ISO only when missing.
if [[ ! -s "$ISO_PATH" ]]; then
  echo
  echo "Downloading Windows 11 IoT Enterprise LTSC 2024 Evaluation from Microsoft..."
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 5 --retry-delay 3 --progress-bar "$MS_URL" -o "$ISO_PATH"
  elif command -v wget >/dev/null 2>&1; then
    wget --show-progress -O "$ISO_PATH" "$MS_URL"
  else
    die "Neither curl nor wget is installed."
  fi
fi
[[ -s "$ISO_PATH" ]] || die "Windows ISO download failed."

echo
echo "Windows ISO is ready: $ISO_PATH"

# Reject a partial VirtIO file left by a failed download.
if [[ -f "$VIRTIO_PATH" ]]; then
  VIRTIO_SIZE="$(stat -c%s "$VIRTIO_PATH" 2>/dev/null || echo 0)"
  if (( VIRTIO_SIZE < 100000000 )); then
    rm -f "$VIRTIO_PATH"
  fi
fi

HAVE_VIRTIO=0
if [[ -s "$VIRTIO_PATH" ]]; then
  HAVE_VIRTIO=1
else
  echo
  echo "Trying to download VirtIO Windows drivers..."
  if command -v curl >/dev/null 2>&1; then
    if curl -fL --connect-timeout 10 --max-time 300 --retry 2 --retry-delay 2 --progress-bar "$VIRTIO_URL" -o "$VIRTIO_PATH"; then
      HAVE_VIRTIO=1
    fi
  elif command -v wget >/dev/null 2>&1; then
    if timeout 300 wget --timeout=10 --tries=2 --show-progress -O "$VIRTIO_PATH" "$VIRTIO_URL"; then
      HAVE_VIRTIO=1
    fi
  fi
fi

if (( HAVE_VIRTIO == 0 )); then
  rm -f "$VIRTIO_PATH"
  echo
  echo "VirtIO download is unavailable from this host."
  echo "Continuing automatically with SATA disk + E1000 network."
  echo "Windows can install without extra drivers in this mode."
fi

VMID="${VMID:-$(pvesh get /cluster/nextid)}"
qm status "$VMID" >/dev/null 2>&1 && die "VMID $VMID already exists."

echo
echo "Creating VM:"
echo "  VMID    : $VMID"
echo "  Name    : $NAME"
echo "  RAM     : ${RAM} MB"
echo "  CPU     : ${CORES} cores"
echo "  Disk    : ${DISK_GB} GB"
echo "  Storage : $STORAGE"

if (( HAVE_VIRTIO == 1 )); then
  echo "  Mode    : VirtIO"
  qm create "$VMID" \
    --name "$NAME" --ostype win11 --machine q35 --bios ovmf \
    --cpu host --sockets 1 --cores "$CORES" --memory "$RAM" --balloon 0 \
    --scsihw virtio-scsi-single --agent enabled=1 \
    --net0 "virtio,bridge=$BRIDGE"

  qm set "$VMID" --efidisk0 "$STORAGE:1,efitype=4m,pre-enrolled-keys=1"
  qm set "$VMID" --tpmstate0 "$STORAGE:1,version=v2.0"
  qm set "$VMID" --scsi0 "$STORAGE:$DISK_GB,discard=on,iothread=1,ssd=1"
  qm set "$VMID" --ide2 "$ISO_VOL,media=cdrom"
  qm set "$VMID" --ide0 "$VIRTIO_VOL,media=cdrom"
  qm set "$VMID" --boot "order=ide2;scsi0"
else
  echo "  Mode    : SATA + E1000 fallback"
  qm create "$VMID" \
    --name "$NAME" --ostype win11 --machine q35 --bios ovmf \
    --cpu host --sockets 1 --cores "$CORES" --memory "$RAM" --balloon 0 \
    --agent enabled=1 --net0 "e1000,bridge=$BRIDGE"

  qm set "$VMID" --efidisk0 "$STORAGE:1,efitype=4m,pre-enrolled-keys=1"
  qm set "$VMID" --tpmstate0 "$STORAGE:1,version=v2.0"
  qm set "$VMID" --sata0 "$STORAGE:$DISK_GB,ssd=1"
  qm set "$VMID" --ide2 "$ISO_VOL,media=cdrom"
  qm set "$VMID" --boot "order=ide2;sata0"
fi

qm set "$VMID" --vga std
qm start "$VMID"

echo
echo "=================================================="
echo " VM created and started successfully"
echo "=================================================="
echo "VMID: $VMID"
echo "Open: Proxmox -> VM $VMID -> Console"

if (( HAVE_VIRTIO == 1 )); then
  echo
  echo "If Windows Setup cannot see the disk:"
  echo "  Load driver -> VirtIO CD -> vioscsi -> w11 -> amd64"
else
  echo
  echo "No VirtIO driver is required during Windows Setup."
  echo "The disk should appear directly."
fi
