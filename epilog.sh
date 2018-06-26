#/bin/bash
set -x

SCRATCH_ROOT=%%SCRATCH_ROOT%%
RSYNCD_HOST=%%RSYNCD_HOST%%

echo "Epilog $(date): begin"

if [ ! -z "$SGE_DATA_OUT" ]; then
  if [ -d $SGE_DATA_OUT ]; then
#    rsync -avzhe "ssh -o StrictHostKeyChecking=no" $SGE_DATA_OUT $SGE_O_LOGNAME@$SGE_O_HOST:$SGE_DATA_OUT_BACK/
    ret=0
    if [ ! -z "$SGE_DATA_OUT_BACK" ]; then
      if [ "$SGE_DATA_OUT_BACK_STORAGE" == "SCRATCH" ]; then
        RSYNC_PASSWORD=ugersync rsync \
          --rsync-path="mkdir -p $SCRATCH_ROOT/$SGE_O_LOGNAME/$SGE_DATA_OUT_BACK && rsync" \
          -rtv $SGE_STDERR_PATH $SGE_STDOUT_PATH $SGE_DATA_OUT/* \
          rsync://ugersync@$RSYNCD_HOST/SCRATCH/$SGE_O_LOGNAME/$SGE_DATA_OUT_BACK/
        ret=$?
      elif [ "$SGE_DATA_OUT_BACK_STORAGE" == "HOME" ]; then
        RSYNC_PASSWORD=ugersync rsync -rtv \
          $SGE_STDERR_PATH $SGE_STDOUT_PATH $SGE_DATA_OUT/* \
          rsync://ugersync@$RSYNCD_HOST/HOME/$SGE_O_LOGNAME/$SGE_DATA_OUT_BACK/
        ret=$?
      else
        echo "ERROR: unknown storage type: $SGE_DATA_OUT_BACK_STORAGE"
      fi
    else
      RSYNC_PASSWORD=ugersync rsync -rtv \
        $SGE_STDERR_PATH $SGE_STDOUT_PATH/* \
        rsync://ugersync@$RSYNCD_HOST/HOME/$SGE_O_LOGNAME/
      ret=$?
      echo "Epilog $(date): transfer data back: home used: $SGE_DATA_OUT_BACK"
    fi
    if [ $ret -ne 0 ]; then
      echo "Epilog $(date): rsync error transferring data back from remote directory $SGE_DATA_OUT to local $SGE_DATA_OUT_BACK"
      echo "local directory $SGE_DATA_OUT_BACK has to exist and have write prmissions for all"
    fi
  else
    echo "Epilog $(date): no output directory: $SGE_DATA_OUT"
  fi
else
  echo "Epilog $(date): SGE_DATA_OUT not defined"
fi
echo "Epilog $(date): end"
