#!/bin/bash
# grubfix.sh - Easily repair Grub
# -----------------------------------------------------------------------------
# Copyright 2010 Steven Pledger <linux.propane@yahoo.com>
# All rights reserved.
#
#   Permission to use, copy, modify, and distribute this software for
#   any purpose with or without fee is hereby granted, provided that
#   the above copyright notice and this permission notice appear in all
#   copies.
#
#   THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESSED OR IMPLIED
#   WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
#   MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
#   IN NO EVENT SHALL THE AUTHORS AND COPYRIGHT HOLDERS AND THEIR
#   CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
#   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
#   LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF
#   USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
#   ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
#   OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT
#   OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
#   SUCH DAMAGE.
# -----------------------------------------------------------------------------

#Exit on most errors
set -e

#set -x

if [ "$(id -un)" != "root" ]; then
  echo "You must be superuser to use this script" >&2
  exit 1
fi

if [ ! -x "$(which dialog)" ]; then
  read -p "This script requires dialog. Install now? (y/n): " ANSWER
  case $ANSWER in
    y | yes)
      apt-get update
      apt-get install dialog
    ;;
    *)
      exit 1
    ;;
  esac
fi

cleanup() {
  sync
  umount -f $MNTPNT/proc 2>/dev/null || true
  umount -f $MNTPNT/dev 2>/dev/null || true
  umount -f $MNTPNT 2>/dev/null || true
  rmdir $MNTPNT 2>/dev/null || true
  rm -rf $TMP
}  

trap "cleanup" 0 1 2 15

TMP=$(mktemp -d /tmp/grubfix.XXXXXX)

# Create a list of partitions
PARTS="$(blkid -o device)"
for dev in $PARTS; do
  dev_FS=$(mount -f --guess-fstype $dev)
  if [ "$dev_FS" != "swap" ] && \
     [ "$dev_FS" != "lvm2pv" ] && \
     [ "$dev_FS" != "ntfs-3g" ] && \
     [ "$dev_FS" != "vfat" ] && \
     [ "$dev_FS" != "squashfs" ] && \
     [ "$dev_FS" != "iso9660" ]
  then
    echo "$dev|$dev_FS" >> $TMP/PARTSLIST
  fi
done

PARTSLIST="$(cat $TMP/PARTSLIST)"
if [ -z "$PARTSLIST" ]; then
  dialog --title 'Error!' \
    --msgbox "No partitions were found" 5 30
  exit 1
fi

NUMPARTS=$(echo "$PARTSLIST" | wc -l)
if [ $NUMPARTS -eq 1 ]; then
  SELECTED=$(echo $PARTSLIST | cut -d'|' -f1)
else
  # Format PARTSLIST for dialog menu
  for p in $PARTSLIST; do
    part="$(echo $p | cut -d'|' -f1)"
    p_FS="$(echo $p | cut -d'|' -f2)"
    MENU="${MENU}$part $p_FS "
  done

  dialog --title "grubfix.sh" --menu "Select your Linux partition:" 15 50 5 \
    $MENU 2>$TMP/SELECTED

  SELECTED=$(cat $TMP/SELECTED)
fi

if [ ! -b "$SELECTED" ]; then
  dialog --title 'Error!' \
    --msgbox "Not a valid partition" 5 30
  exit 1
fi

SELECTED_FS=$(grep "^$SELECTED" $TMP/PARTSLIST | cut -d'|' -f2)

# Create list of hard drives
DRIVES=$(fdisk -l 2>/dev/null | grep '^Disk /dev' | tr ' ' : | cut -d: -f2)
for d in $DRIVES; do
  d_SIZE=$(fdisk -l 2>/dev/null | grep "^Disk $d" | cut -d' ' -f3-4 | tr -d ',' | tr -d ' ')
  echo "$d|$d_SIZE" >> $TMP/DRIVESLIST
done

DRIVESLIST=$(cat $TMP/DRIVESLIST)
if [ -z "$DRIVESLIST" ]; then
  dialog --title 'Error!' \
    --msgbox "No drives were found" 5 30
  exit 1
fi

NUMDRIVES=$(echo "$DRIVESLIST" | wc -l)
if [ $NUMDRIVES -eq 1 ]; then
  GRUB_TARGET=$(echo $DRIVESLIST | cut -d'|' -f1)
else
  for drv in $DRIVESLIST; do
    drive_SIZE=$(echo $drv | cut -d'|' -f2)
    drive=$(echo $drv | cut -d'|' -f1)
    drive_MENU="${drive_MENU}$drive $drive_SIZE "
  done
  FIRSTDRIVE=$(echo $DRIVESLIST | head -n 1 | cut -d'|' -f1)
  dialog --title "Where do you want to install Grub?" --menu \
"Grub is usually installed to the MBR of the first hard drive, \
which in your case is $FIRSTDRIVE\n\n\
Your MBR will be backed up before installing. \
If something fails, you can restore it with: \n\
cat mbr.bin > /dev/sdX" 15 40 5 $drive_MENU 2>/$TMP/GRUB_TARGET
  GRUB_TARGET=$(cat $TMP/GRUB_TARGET)
fi

if [ ! -b "$GRUB_TARGET" ]; then
  dialog --title 'Error!' \
    --msgbox "Not a valid Grub target" 5 30
  exit 1
fi

dialog --title "Last chance" --yesno \
"Selected Linux partition is:\n\
$SELECTED\n\n\
Grub will be installed to:\n\
$GRUB_TARGET\n\n\
Do you want to continue?" 12 35

MNTPNT=$(mktemp -d /mnt/mount.XXXXXX)

mount -t $SELECTED_FS $SELECTED $MNTPNT
mount -t proc none $MNTPNT/proc
mount --bind /dev $MNTPNT/dev

dd if=$GRUB_TARGET of=mbr.bin bs=512 count=1
chroot $MNTPNT grub-install $GRUB_TARGET

dialog --title 'Success!' \
  --msgbox "Grub has been successfully repaired" 5 40

exit 0
