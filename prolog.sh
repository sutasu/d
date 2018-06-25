#/bin/bash
set -x

SCRATCH_ROOT=%%SCRATCH_ROOT%%
RSYNCD_HOST=%%RSYNCD_HOST%%

echo "Prolog $(date): begin"

if [ ! -z "$SGE_DATA_IN" ]; then
  if [ ! -d $SGE_DATA_IN ]; then
    ret=0
    if [ "$SGE_DATA_IN_SRC_STORAGE" == "HOME" ]; then
      mkdir -p $SGE_DATA_IN
      chmod a+wx $SGE_DATA_IN
      RSYNC_PASSWORD=ugersync rsync -rtv \
        rsync://ugersync@$RSYNCD_HOST/HOME/$SGE_O_LOGNAME/$SGE_DATA_IN_SRC/* \
        $SGE_DATA_IN/
      ret=$?
    elif [ "$SGE_DATA_IN_SRC_STORAGE" == "SCRATCH" ]; then
      mkdir -p $SGE_DATA_IN
      chmod a+wx $SGE_DATA_IN
      RSYNC_PASSWORD=ugersync rsync \
        -rtv rsync://ugersync@$RSYNCD_HOST/SCRATCH/$SGE_DATA_IN_SRC/* \
        $SGE_DATA_IN/
      ret=$?
    else
      echo "Unknown storage type: $SGE_DATA_IN_SRC_STORAGE"
    fi
    if [ $ret -ne 0 ]; then
      echo "Prolog $(date): rsync error transferring data"
      # remove directory if empty
      rmdir $SGE_DATA_IN
    fi
  else
    echo "Prolog $(date): already there: $SGE_DATA_IN"
  fi
else
  echo "Prolog $(date): SGE_DATA_IN not defined"
fi
echo "Prolog $(date): end"
