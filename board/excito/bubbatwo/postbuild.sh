#!/bin/sh

ROOT=$1

install -m755 board/excito/bubbatwo/bubbainstall.sh $ROOT/usr/sbin/bubbainstall.sh

cat << EOF >> $ROOT/etc/rc.local
echo "Starting Excito B2 install"
/usr/sbin/bubbainstall.sh >/dev/null 2>&1
EOF

