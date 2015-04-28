#!/bin/bash
id=${1:-'NOTHING'}
op=${2:-'NOTHING'}

if [ $id == 'NOTHING' ]; then
  echo "id is not provided, usage $0 <osd id> [out|reset]"
  exit 1;
fi

if [ $op == 'NOTHING' ]; then
  echo "Operation is not provided, usage $0 <osd id> [out|reset]"
  exit 1;
fi

function osd_out {
  ceph osd out $id
}

function osd_reset {
  ceph osd out $id
  service ceph stop osd.${id}
  ceph osd crush remove osd.${id}
  ceph auth del osd.${id}
  ceph osd rm ${id}
  df -h | grep -q "/var/lib/ceph/osd/ceph-${id}" ; rv=$?
  if [ $rv -eq 0 ]; then
    disk=`df -h | grep /var/lib/ceph/osd/ceph-${id}| awk '{print $1}' | sed 's#/dev/\([a-z][a-z]*\)[0-9]#\1#'`
  fi
  umount /var/lib/ceph/osd/ceph-${id}
  if [ -b /dev/${disk}1 ]; then
    dd if=/dev/zero of=/dev/${disk}1 bs=1M count=1000
  fi
  if [ -b /dev/${disk}2 ]; then
    dd if=/dev/zero of=/dev/${disk}2 bs=1M count=1000
  fi
  sed -i '/\/dev\/${disk}[12]/d' /etc/fstab
  if [ -b /dev/${disk}2 ]; then 
    parted --script -a optimal /dev/${disk} rm 2
  fi
  if [ -b /dev/${disk}1 ]; then
    parted --script -a optimal /dev/${disk} rm 1
  fi
  cat << CEPH_REMOVE_OSD_CONFIG | puppet apply 
    ceph_config {
      "osd.${id}/host":      ensure => absent;
      "osd.${id}/devs":      value => '/dev/${disk}2', ensure => absent;
      "osd.${id}/cluster addr": ensure => absent;
      "osd.${id}/public addr": ensure => absent;
      "osd.${id}/osd journal": ensure => absent;
    }
CEPH_REMOVE_OSD_CONFIG
  sed -i '/\[osd.${id}\]/d' /etc/ceph/ceph.conf
  n=1
  while [ $n -le 4 ]; do
  cat << CEPH_ADD_OSD | puppet apply
    ceph::osd::disk_setup {'/dev/${disk}':
      osd_journal_type => 'first_partition',
      osd_journal_size => 10,
    }
    ceph::osd::device {'/dev/${disk}':
      osd_journal_type => 'first_partition',
      osd_journal_size => 10,
    }
    Exec { path => [ "/bin/", "/sbin/" , "/usr/bin/", "/usr/sbin/", "/usr/local/bin/","/usr/local/sbin/" ] }
    ::ceph::key { 'admin':
      secret   => 'AQCNhbZTCKXiGhAAWsXesOdPlNnUSoJg7BZvsw==',
    }
CEPH_ADD_OSD
  n=$(($n+1))
  done
  newid=`df -h | grep "/dev/${disk}[12]" | cut -f2 -d'-'`
  ceph-osd -i $newid --mkjournal
  cat << CEPH_ADD_OSD | puppet apply 
    ceph::osd::device {'/dev/${disk}':
      osd_journal_type => 'first_partition',
      osd_journal_size => 10,
    }
    Exec { path => [ "/bin/", "/sbin/" , "/usr/bin/", "/usr/sbin/", "/usr/local/bin/","/usr/local/sbin/" ] }
    ::ceph::key { 'admin':
      secret   => 'AQCNhbZTCKXiGhAAWsXesOdPlNnUSoJg7BZvsw==',
    }
CEPH_ADD_OSD
}

if [ $op == 'out' ]; then
  osd_out
elif [ $op == 'reset' ]; then
  osd_reset
fi
