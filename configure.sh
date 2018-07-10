#!/bin/bash
# generate ssh key for sge user on installer node and
# install puppet module responsible for installing sge user ssh key on compute nodes
# add complexes

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TORTUGA_SETUP_FILES_DIR=/etc/puppetlabs/code/environments/production/modules/tortuga_kit_uge/files/setup
SW_PROFILE=execd
#SW_PROFILE=default
TORTUGA_SETUP_FILES_DM_CONFIG=$TORTUGA_SETUP_FILES_DIR/compute-conf/$SW_PROFILE
SGE_USER_HOME=/home/sge
LOCAL_PATH_COMPLEX=lpath
LOCAL_PATH_BOOL_COMPLEX=lpath_bool
SHARED_PATH_COMPLEX=spath
SHARED_PATH_BOOL_COMPLEX=spath_bool
LOAD_SENSOR_DIR=$SGE_ROOT/setup
# remote cluster exec node local data directory
SGE_LOCAL_STORAGE_ROOT=/tmp/sge_data
# remote cluster shared data directory
SGE_SHARED_STORAGE_ROOT=/tmp/sge_shared
# local cluster shared data directory
SCRATCH_ROOT=/tmp/sge_shared
RSYNCD_HOST=$(hostname)
#RSYNCD_HOST=%%RSYNCD_HOST%%

clean() {
  rm -rf $SGE_USER_HOME/.ssh
  rm -f /etc/puppetlabs/code/environments/production/modules/sge_ssh_key/manifests/init.pp
  pkill -f "rsync --daemon"
}

add_complex() {
  local nm=$1
  local type=$2
  local default=${3:-NONE}
  COMPLEX_STR="$nm $nm $type == YES NO $default 0 NO"
  TMP_COMPLEX_FILE=/tmp/complex
  qconf -sc > $TMP_COMPLEX_FILE
  if ! grep '$COMPLEX_STR' $TMP_COMPLEX_FILE ; then
    echo "$COMPLEX_STR" >> $TMP_COMPLEX_FILE
    qconf -Mc $TMP_COMPLEX_FILE
  else
    echo "Complex $nm is already present"
  fi
}

add_pro_epi_ls() {
  local nodes="$@"
  #
  # prepare load sensor
  sed "s|%%SGE_STORAGE_ROOT%%|$SGE_LOCAL_STORAGE_ROOT|; s|%%SGE_COMPLEX_NAME%%|$LOCAL_PATH_COMPLEX|" $SCRIPT_DIR/load-sensor.sh > /tmp/lls.sh
  chmod a+x /tmp/lls.sh
  sed "s|%%SGE_STORAGE_ROOT%%|$SGE_SHARED_STORAGE_ROOT|; s|%%SGE_COMPLEX_NAME%%|$SHARED_PATH_COMPLEX|" $SCRIPT_DIR/load-sensor.sh > /tmp/sls.sh
  chmod a+x /tmp/sls.sh
  sed "s|%%RSYNCD_HOST%%|$RSYNCD_HOST|; s|%%SCRATCH_ROOT%%|$SCRATCH_ROOT|" $SCRIPT_DIR/epilog.sh > /tmp/epilog.sh
  chmod a+x /tmp/epilog.sh
  sed "s|%%RSYNCD_HOST%%|$RSYNCD_HOST|; s|%%SCRATCH_ROOT%%|$SCRATCH_ROOT|" $SCRIPT_DIR/prolog.sh > /tmp/prolog.sh
  chmod a+x /tmp/prolog.sh
  for n in $nodes; do
    sudo su - sge -c "scp -o StrictHostKeyChecking=no /tmp/lls.sh /tmp/sls.sh /tmp/epilog.sh /tmp/prolog.sh sge@${n}:${LOAD_SENSOR_DIR}"
    sudo su - sge -c "ssh $n 'bash -c \"mkdir -p $SCRATCH_ROOT; chmod a+wx $SCRATCH_ROOT; mkdir -p $SGE_LOCAL_STORAGE_ROOT; chmod a+wx $SGE_LOCAL_STORAGE_ROOT\"'"
  done
}

add_pro_epi_log() {
  local pro_epi=$1
  local sf=$pro_epi.sh
  local tmpsf=/tmp/$sf
  sed "s|%%RSYNCD_HOST%%|$RSYNCD_HOST|; s|%%SCRATCH_ROOT%%|$SCRATCH_ROOT|" $SCRIPT_DIR/$sf > $tmpsf
  chmod a+x $tmpsf
  for n in $(qconf -sel); do
    sudo su - sge -c "scp -o StrictHostKeyChecking=no $tmpsf sge@${n}:${LOAD_SENSOR_DIR}"
  done
  # queue level
#  qconf -mattr queue $pro_epi $LOAD_SENSOR_DIR/$sf all.q
  # execd level
#  qconf -mconf node
}

FORCE=0
if [ "$1" == '--force' ]; then
  FORCE=1
  clean
fi

# generate ssh key for sge user
if [ ! -f $SGE_USER_HOME/.ssh/id_rsa.pub ]; then
  mkdir -p $SGE_USER_HOME/.ssh
  ssh-keygen -q -f $SGE_USER_HOME/.ssh/id_rsa -t rsa -N ''
  touch $SGE_USER_HOME/.ssh/authorized_keys
  chmod 0600 $SGE_USER_HOME/.ssh/authorized_keys
  chown -R sge.sge $SGE_USER_HOME/.ssh
else
  echo "ssh key for sge user already exists"
fi

# add manifest for installing ssh key for sge user
if [ ! -f /etc/puppetlabs/code/environments/production/modules/sge_ssh_key/manifests/init.pp ]; then
  ssh_key=$(awk '{print $2}' $SGE_USER_HOME/.ssh/id_rsa.pub)
  mkdir -p /etc/puppetlabs/code/environments/production/modules/sge_ssh_key/manifests
  cat > /etc/puppetlabs/code/environments/production/modules/sge_ssh_key/manifests/init.pp <<EOF
class sge_ssh_key {
  ssh_authorized_key { 'sge_ssh_key':
    ensure => present,
    key    => '$ssh_key',
    type   => 'ssh-rsa',
    user   => 'sge'
  }
}
EOF
else
  echo "sge ssh puppet module already exists"
fi

# add module to regular software profile (separate software profile may be created later)
if ! grep sge_ssh_key /etc/puppetlabs/code/environments/production/data/tortuga-extra.yaml ; then
  cat >> /etc/puppetlabs/code/environments/production/data/tortuga-extra.yaml <<EOF
classes:
  - sge_ssh_key

EOF
else
  echo "sge puppet module is already in hiera"
fi

# add manifest for creating data storage root directories
if [ ! -f /etc/puppetlabs/code/environments/production/modules/storage/manifests/init.pp ]; then
  mkdir -p /etc/puppetlabs/code/environments/production/modules/storage/manifests
  cat > /etc/puppetlabs/code/environments/production/modules/storage/manifests/init.pp <<EOF
class storage {
  file { [ '$SGE_LOCAL_STORAGE_ROOT', '$SGE_SHARED_STORAGE_ROOT']:
    ensure => 'directory',
    owner  => 'sge',
    group  => 'wheel',
    mode   => '0777',
  }
}
EOF
else
  echo "sge storage puppet module already exists"
fi

# add module create storage root directories to regular software profile (separate software profile may be created later)
if ! grep storage /etc/puppetlabs/code/environments/production/data/tortuga-extra.yaml ; then
  cat >> /etc/puppetlabs/code/environments/production/data/tortuga-extra.yaml <<EOF
  - storage

EOF
else
  echo "storage puppet module is already in hiera"
fi


#install rsync
if true; then
  sudo yum install rsync
  cat > /etc/rsyncd.conf <<EOF
lock file = /var/run/rsync.lock
log file = /var/log/rsyncd.log
pid file = /var/run/rsyncd.pid
[HOME]
        path = /home
        comment = home
        read only = no
        write only = no
        uid = $(id -u sge)
        gid = $(id -g sge)
        incoming chmod = a+w
        auth users = ugersync
        secrets file = /etc/rsyncd.secrets
[SCRATCH]
        path = /tmp/sge_shared
        comment = shared
        read only = no
        write only = no
        uid = $(id -u sge)
        gid = $(id -g sge)
        incoming chmod = a+w
        auth users = ugersync
        secrets file = /etc/rsyncd.secrets
EOF
  cat > /etc/rsyncd.secrets <<EOF
ugersync:ugersync
EOF
  sudo chmod 600 /etc/rsyncd.secrets
  rsync --daemon
  echo "Started rsync daemon"
else
# install rsyncd in installer node
pusudo chmod 600 /etc/ppet module install puppetlabs-rsync --version 1.1.0
if [ ! -f /etc/puppetlabs/code/environments/production/modules/rsyncd/manifests/init.pp ]; then
  mkdir -p /etc/puppetlabs/code/environments/production/modules/rsyncd/manifests
  cat > /etc/puppetlabs/code/environments/production/modules/rsyncd/manifests/init.pp <<EOF
rsync::server::module{ 'rsyncd_home':
  path    => \$base,
  require => File[\$base],
}
rsync::server::module{ 'rsyncd_scratch':
  path    => \$base,
  require => File[\$base],
}
EOF
else
  echo "rsyncd puppet module already exists"
fi
# add rsyncd variables to hiera
if ! grep 'rsync::server::modules' /etc/puppetlabs/code/environments/production/hiera.yaml; then
cat >> /etc/puppetlabs/code/environments/production/hiera.yaml <<EOF
rsync::server::modules:
  rsyncd_home:
    path: /home
    incoming_chmod: false
    outgoing_chmod: false
  rsyncd_scratch:
    path: /tmp
    read_only: false
EOF
else
  echo "rsync is already in hiera"
fi
fi

# add complex
add_complex $LOCAL_PATH_COMPLEX RESTRING
add_complex $LOCAL_PATH_BOOL_COMPLEX BOOL 0
add_complex $SHARED_PATH_COMPLEX RESTRING
add_complex $SHARED_PATH_BOOL_COMPLEX BOOL 0

# add prolog epilog and load sensor to existing nodes
#add_pro_epi_ls $(qconf -sel)

# configure qsub wrapper script
sed "s|%%SCRATCH_ROOT%%|$SCRATCH_ROOT|; \
     s|%%SGE_LOCAL_STORAGE_ROOT%%|$SGE_LOCAL_STORAGE_ROOT|; \
     s|%%SGE_SHARED_STORAGE_ROOT%%|$SGE_SHARED_STORAGE_ROOT|; \
     s|%%LOCAL_PATH_COMPLEX%%|$LOCAL_PATH_COMPLEX|; \
     s|%%LOCAL_PATH_BOOL_COMPLEX%%|$LOCAL_PATH_BOOL_COMPLEX|; \
     s|%%SHARED_PATH_COMPLEX%%|$SHARED_PATH_COMPLEX|; \
     s|%%SHARED_PATH_BOOL_COMPLEX%%|$SHARED_PATH_BOOL_COMPLEX|" \
     $SCRIPT_DIR/qsub-wrapper.sh > $TORTUGA_ROOT/bin/qsub-wrapper.sh
chmod a+x $TORTUGA_ROOT/bin/qsub-wrapper.sh

# configure scale script
sed "s|%%LOCAL_PATH_COMPLEX%%|$LOCAL_PATH_COMPLEX|; \
     s|%%LOCAL_PATH_BOOL_COMPLEX%%|$LOCAL_PATH_BOOL_COMPLEX|; \
     s|%%SHARED_PATH_COMPLEX%%|$SHARED_PATH_COMPLEX|; \
     s|%%SHARED_PATH_BOOL_COMPLEX%%|$SHARED_PATH_BOOL_COMPLEX|" \
     $SCRIPT_DIR/scale-up.sh > $TORTUGA_ROOT/bin/scale-up.sh
chmod a+x $TORTUGA_ROOT/bin/scale-up.sh

# add load sensors and prolog/epilog to Tortuga stup files
mkdir -p $TORTUGA_SETUP_FILES_DM_CONFIG/load_sensor \
     $TORTUGA_SETUP_FILES_DM_CONFIG/prolog \
     $TORTUGA_SETUP_FILES_DM_CONFIG/epilog

sed "s|%%SGE_STORAGE_ROOT%%|$SGE_LOCAL_STORAGE_ROOT|; \
     s|%%SGE_COMPLEX_NAME%%|$LOCAL_PATH_COMPLEX|; \
     s|%%SGE_BOOL_COMPLEX_NAME%%|$LOCAL_PATH_BOOL_COMPLEX|; \
     s|%%DEPTH%%|1|" \
     $SCRIPT_DIR/load-sensor.sh > $TORTUGA_SETUP_FILES_DM_CONFIG/load_sensor/lls.sh
chmod a+x $TORTUGA_SETUP_FILES_DM_CONFIG/load_sensor/lls.sh

sed "s|%%SGE_STORAGE_ROOT%%|$SCRATCH_ROOT|; \
     s|%%SGE_COMPLEX_NAME%%|$SHARED_PATH_COMPLEX|; \
     s|%%SGE_BOOL_COMPLEX_NAME%%|$SHARED_PATH_BOOL_COMPLEX|; \
     s|%%DEPTH%%|1|" \
     $SCRIPT_DIR/load-sensor.sh > $TORTUGA_SETUP_FILES_DM_CONFIG/load_sensor/sls.sh
chmod a+x $TORTUGA_SETUP_FILES_DM_CONFIG/load_sensor/sls.sh

sed "s|%%RSYNCD_HOST%%|$RSYNCD_HOST|; \
     s|%%SCRATCH_ROOT%%|$SCRATCH_ROOT|" \
     $SCRIPT_DIR/epilog.sh > $TORTUGA_SETUP_FILES_DM_CONFIG/epilog/epilog.sh
chmod a+x $TORTUGA_SETUP_FILES_DM_CONFIG/epilog/epilog.sh

sed "s|%%RSYNCD_HOST%%|$RSYNCD_HOST|; \
     s|%%SCRATCH_ROOT%%|$SCRATCH_ROOT|" \
     $SCRIPT_DIR/prolog.sh > $TORTUGA_SETUP_FILES_DM_CONFIG/prolog/prolog.sh
chmod a+x $TORTUGA_SETUP_FILES_DM_CONFIG/prolog/prolog.sh

