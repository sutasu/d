#!/bin/sh
#

PATH=/bin:/usr/bin

ARCH=`$SGE_ROOT/util/arch`
HOST=`$SGE_ROOT/utilbin/$ARCH/gethostname -name`

ls_log_file=/tmp/$(basename "${BASH_SOURCE[0]}").dbg
#printenv
# uncomment this to log load sensor startup  
#echo `date`:$$:I:load sensor `basename $0` started >> $ls_log_file

SGE_STORAGE_ROOT=%%SGE_STORAGE_ROOT%%
DEPTH=%%DEPTH%%
#mkdir -p $SGE_CACHE_DATA_DIR
cd $SGE_STORAGE_ROOT

SGE_COMPLEX_NAME=%%SGE_COMPLEX_NAME%%

end=false
while [ $end = false ]; do

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
   # send load value arch
   #
   complex=
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
   echo "$HOST:$SGE_COMPLEX_NAME:$complex"

   # ---------------------------------------- 
   # send mark for end of load report
   echo "end"
done

# uncomment this to log load sensor shutdown  
#echo `date`:$$:I:load sensor `basename $0` exiting >> $ls_log_file
