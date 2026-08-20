#!/usr/bin/env bash
set -Eeuo pipefail

# Tiny11 VM installer for Proxmox VE
# Requires a Tiny11 ISO already uploaded to an ISO-capable Proxmox storage.
# Defaults are tuned for a lightweight VM.

NAME="${NAME:-Tiny11}"
RAM="${RAM:-2048}"
CORES="${CORES:-2}"
DISK_GB="${DISK_GB:-32}"
BRIDGE="${BRIDGE:-vmbr0}"
STORAGE="${STORAGE:-local-lvm}"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

echo "=========================================="
echo " Tiny11 VM installer for Proxmox VE"
echo "=========================================="

[[ $EUID -eq 0 ]] || die "Run as root."
command -v qm >/dev/null 2>&1 || die "Run this on the Proxmox host."
command -v pvesm >/dev/null 2>&1 || die "pvesm not found."
command -v pvesh >/dev/null 2>&1 || die "pvesh not found."

# Check storage
pvesm status | awk -v s="$STORAGE" 'NR>1 && $1==s && $3=="active"{ok=1} END{exit !ok}' \
  || die "Storage '$STORAGE' is not active. Override with STORAGE=your-storage."

# Find Tiny11/Windows ISO
if [[ -n "${WIN_ISO:-}" ]]; then
  ISO="$WIN_ISO"
else
  mapfile -t ISOS < <(
    for s in $(pvesm status | awk 'NR>1 && $3=="active"{print $1}'); do
      pvesm list "$s" --content iso 2>/dev/null \
        | awk 'NR>1{print $1}' \
        | grep -Ei '(tiny11|windows|win11).*\.iso$' || true
    done
  )

  [[ ${#ISOS[@]} -gt 0 ]] || {
    echo
    echo "No Tiny11/Windows ISO found."
    echo "Upload tiny11.iso first:"
    echo "  Proxmox -> local -> ISO Images -> Upload"
    exit 2
  }

  if [[ ${#ISOS[@]} -eq 1 ]]; then
    ISO="${ISOS[0]}"
  else
    echo
    echo "Available ISO images:"
    for i in "${!ISOS[@]}"; do
      printf "  [%d] %s\n" "$((i+1))" "${ISOS[$i]}"
    done
    read -rp "Choose ISO [1-${#ISOS[@]}]: " n
    [[ "$n" =~ ^[0-9]+$ ]] || die "Invalid selection."
    (( n >= 1 && n <= ${#ISOS[@]} )) || die "Invalid selection."
    ISO="${ISOS[$((n-1))]}"
  fi
fi

pvesm path "$ISO" >/dev/null 2>&1 || die "ISO not found: $ISO"

# VirtIO ISO
mkdir -p /var/lib/vz/template/iso
VIRTIO_PATH="/var/lib/vz/template/iso/virtio-win.iso"
VIRTIO_VOL="local:iso/virtio-win.iso"

if [[ ! -s "$VIRTIO_PATH" ]]; then
  echo "Downloading VirtIO drivers..."
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 \
      https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso \
      -o "$VIRTIO_PATH"
  else
    wget -O "$VIRTIO_PATH" \
      https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
  fi
fi

[[ -s "$VIRTIO_PATH" ]] || die "VirtIO ISO download failed."

VMID="${VMID:-$(pvesh get /cluster/nextid)}"

echo
echo "VMID:    $VMID"
echo "Name:    $NAME"
echo "RAM:     ${RAM} MB"
echo "CPU:     ${CORES} cores"
echo "Disk:    ${DISK_GB} GB"
echo "Storage: $STORAGE"
echo "ISO:     $ISO"
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
qm set "$VMID" --ide2 "$ISO,media=cdrom"
qm set "$VMID" --ide0 "$VIRTIO_VOL,media=cdrom"
qm set "$VMID" --boot "order=ide2;scsi0"
qm set "$VMID" --vga std

echo
echo "Starting Tiny11 VM..."
qm start "$VMID"

echo
echo "=========================================="
echo " Tiny11 VM created successfully"
echo "=========================================="
echo "VMID: $VMID"
echo
echo "Open: Proxmox -> VM $VMID -> Console"
echo
echo "If the Windows installer cannot see the disk:"
echo "Load driver -> VirtIO CD -> vioscsi -> w11 -> amd64"
echo
echo "After installation, run from the VirtIO CD:"
echo "virtio-win-guest-tools.exe"
