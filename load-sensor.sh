#!/bin/sh
#

PATH=/bin:/usr/bin

ARCH=`$SGE_ROOT/util/arch`
HOST=`$SGE_ROOT/utilbin/$ARCH/gethostname -name`

ls_log_file=/tmp/$(basename "${BASH_SOURCE[0]}").dbg
#printenv
# uncomment this to log load sensor startup  
echo `date +%F-%H-%M-%S.%3N`:$$:I:load sensor `basename $0` started >> $ls_log_file

SGE_STORAGE_ROOT=%%SGE_STORAGE_ROOT%%
DEPTH=%%DEPTH%%
SGE_COMPLEX_NAME=%%SGE_COMPLEX_NAME%%
SGE_BOOL_COMPLEX_NAME=%%SGE_BOOL_COMPLEX_NAME%%

end=false
while [ $end = false ]; do
  echo `date +%F-%H-%M-%S.%3N`:$$:I:load sensor `basename $0` in loop >> $ls_log_file
  # ---------------------------------------- 
  # wait for an input
  #
  read input
  result=$?
  if [ $result != 0 ]; then
    end=true
    break
  fi
   
  if [ "$input" = "quit" ]; then
    end=true
    break
  fi

  # ---------------------------------------- 
  # send mark for begin of load report
  echo "begin"

  # ---------------------------------------- 
  # send load values
  #
  complex=
  bool_complex=
  if [ -d $SGE_STORAGE_ROOT ]; then
    bool_complex=1
    cd $SGE_STORAGE_ROOT
    for d in $(find * -maxdepth $DEPTH -mindepth $DEPTH); do
      v=$(set -o pipefail; echo "$(basename "$d")" | base64 --decode)
      if [ $? -eq 0 ]; then
        if [ -z "$complex" ]; then
          complex=$v
        else
          complex="${complex},${v}"
        fi
      fi
    done
    cd - > /dev/null 2>&1
  fi
  echo "$HOST:$SGE_COMPLEX_NAME:$complex"
  echo "$HOST:$SGE_BOOL_COMPLEX_NAME:$bool_complex"
  echo `date +%F-%H-%M-%S.%3N`:$$:I:load sensor `basename $0` $HOST:$SGE_COMPLEX_NAME:$complex >> $ls_log_file
  echo `date +%F-%H-%M-%S.%3N`:$$:I:load sensor `basename $0` $HOST:$SGE_BOOL_COMPLEX_NAME:$complex >> $ls_log_file

  # ---------------------------------------- 
  # send mark for end of load report
  echo "end"
done

# uncomment this to log load sensor shutdown  
echo `date +%F-%H-%M-%S.%3N`:$$:I:load sensor `basename $0` exiting >> $ls_log_file
