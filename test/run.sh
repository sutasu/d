#!/bin/bash
set -e
readonly job_input_dir=input
readonly job_output_dir=out

readonly src=(HOME SCRATCH)
readonly dest=(LOCAL SCRATCH)
readonly back=(HOME SCRATCH)
declare -A in_dir
readonly in_dir=([HOME]="$HOME/$job_input_dir" [SCRATCH]="/tmp/sge_shared/$USER/$job_input_dir")
declare -A out_dir
readonly out_dir=([HOME]="$HOME/$job_output_dir" [SCRATCH]="/tmp/sge_shared/$USER/$job_output_dir")

echo "in_dir=${in_dir[@]}"
echo "out_dir=${out_dir[@]}"

for s in ${src[@]}; do
  echo $s
  for d in ${dest[@]}; do
    echo $d
    for b in ${back[@]}; do
      echo $b
#      rm -rf ${in_dir[$s]} ${out_dir[$b]}
      mkdir -p ${in_dir[$s]} ${out_dir[$b]}
      input_file=hello_${s}_${d}_${b}
      touch ${in_dir[$s]}/$input_file
      bash -x qsub-wrapper.sh -src $s/$job_input_dir -dest $d -sync-back /home/$USER/out:$b/$job_output_dir -j y job.sh
      sleep 2
      if [ ! -f "${out_dir[$b]}/$input_file" ]; then
        echo "ERROR: $s, $d, $b"
        exit 1
      fi
    done
  done
done


#bash -x qsub-wrapper.sh -src HOME/in -dest LOCAL -sync-back /home/centos/out:HOME/out -j y t.sh
#bash -x qsub-wrapper.sh -src HOME/in -dest LOCAL -sync-back /home/centos/out:SCRATCH/out -j y t.sh
#bash -x qsub-wrapper.sh -src HOME/in -dest SCRATCH -sync-back /home/centos/out:HOME/out -j y t.sh
#bash -x qsub-wrapper.sh -src HOME/in -dest SCRATCH -sync-back /home/centos/out:SCRATCH/out -j y t.sh
#bash -x qsub-wrapper.sh -src SCRATCH/in -dest LOCAL -sync-back /home/centos/out:HOME/out -j y t.sh
#bash -x qsub-wrapper.sh -src SCRATCH/in -dest LOCAL -sync-back /home/centos/out:SCRATCH/out -j y t.sh
#bash -x qsub-wrapper.sh -src SCRATCH/in -dest SCRATCH -sync-back /home/centos/out:HOME/out -j y t.sh
#bash -x qsub-wrapper.sh -src SCRATCH/in -dest SCRATCH -sync-back /home/centos/out:SCRATCH/out -j y t.sh



