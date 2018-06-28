#!/bin/bash
# positional parameters:
# job_ids
# job_slots
# job_users
# queue_available_slots
# queue_total_slots
# queue_reserved_slots
# queue_names


SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOG_FILE=/tmp/scale-up.log
VERBOSE=0
QUEUE=all.q
TORTUGA_ROOT=/opt/tortuga
HARDWARE_PROFILE=aws
SOFTWARE_PROFILE=execd
SLOTS_ON_EXECD=2
LOCAL_PATH_COMPLEX=%%LOCAL_PATH_COMPLEX%%
LOCAL_PATH_BOOL_COMPLEX=%%LOCAL_PATH_BOOL_COMPLEX%%
SHARED_PATH_COMPLEX=%%SHARED_PATH_COMPLEX%%
SHARED_PATH_BOOL_COMPLEX=%%SHARED_PATH_BOOL_COMPLEX%%
#SYNC_BACK_PATH_COMPLEX=sync_back
SYNC_BACK_ENV_VAR=SYNC_BACK
# local data storage on remote compute nodes
SGE_LOCAL_STORAGE_ROOT=/tmp/sge_data
SGE_SHARED_STORAGE_ROOT=/tmp/sge_shared
LOAD_SENSOR_DIR=$SGE_ROOT/setup
# local cluster shared directory
SCRATCH_ROOT=/tmp/sge_shared
RSYNCD_HOST=$(hostname)
#RSYNCD_HOST=%%RSYNCD_HOST%%
#RSYNC="sudo su - sge -c "

out() {
 echo "$@" | tee -a "$LOG_FILE" >&2
}

log() {
 if [ $VERBOSE -eq 1 ]; then
   Out "$@"
 else
   echo "$@" >> "$LOG_FILE"
 fi
}

SPINNER='/-\|'
SPINNER_LEN=${#SPINNER}
DOT_PROGRESS=yes

progress() {
  local cnt=$1
  if [ -z $DOT_PROGRESS ]; then
    printf "%s\r" "$cnt ${SPINNER:cnt%SPINNER_LEN:1}"
  else
    echo -n "."
  fi
}


# bash >= 4.3 can pass arrays by reference but for now
# pass arrays as strings
upload_data() {
#  local -n nodes=$1
#  local -n ssh_available=$2
#  local -n from=$3
#  local -n to=$4
  local nodes=( $(echo "$1") )
  local ssh_available=( $(echo "$2") )
  local from=( $(echo "$3") )
  local to=( $(echo "$4") )
  local node_cnt=0
  log "Upload data:"
  log "  nodes=${nodes[@]}"
  log "  ssh_available=${ssh_available[@]}"
  log "  from=${from[@]}"
  log "  to=${to[@]}"
  out "Waiting to start data transfer..."
  for ((data_cnt=0; data_cnt<${#from[@]}; data_cnt++)) {
    if [ $node_cnt -ge ${#nodes[@]} ]; then
      node_cnt=0
    fi
    log "data_cnt=$data_cnt, node_cnt=$node_cnt"
    node=${nodes[$node_cnt]}
    if [ ${ssh_available[$node_cnt]} -eq 0 ]; then
      progress
      log "Checking if ssh is available for $node"
      sudo su - sge -c "ssh -q -o \"BatchMode=yes\" -o \"ConnectTimeout=5\" sge@$node \"echo 2>&1\""
      if [ $? -ne 0 ]; then
        log "ssh not available on $node yet"
        data_cnt=$((data_cnt - 1))
        node_cnt=$((node_cnt + 1))
        sleep 5
        continue
      else
        ssh_available[$node_cnt]=1
        out "ssh available on $node"
      fi
    fi
    data_path=${from[$data_cnt]}
    path_to=${to[$data_cnt]}
    if [ $ASYNC -eq 1 ]; then
      rsync -avzhe "ssh -o StrictHostKeyChecking=no" \
        --rsync-path="mkdir -p $SGE_LOCAL_STORAGE_ROOT/$path_to && rsync" \
        $data_path sge@$node:$path_to/ &
      RSYNC_PIDS+=($!)
    else
      out "Transferring data from $data_path to sge@$node:$path_to/"
      #cm="Dgo+s,ugo+w,Fgo+w,+X"
      cm="ugo+w"
      sudo su - sge -c "rsync --no-p --no-g --chmod=$cm -avzhe \"ssh -o StrictHostKeyChecking=no\" \
        --rsync-path=\"mkdir -p $path_to && chmod a+rwx $(dirname $path_to) && rsync\" \
        $data_path/* sge@$node:$path_to/"
      ret=$?
      if [ $ret -ne 0 ]; then
        out "error code from rsync: $ret"
      fi
    fi
    node_cnt=$((node_cnt + 1))
  }
}

log "Start: "${BASH_SOURCE[@]}""

ASYNC=0
RSYNC_PIDS=()

job_ids=(${1//,/ })
#IFS=',' read -ra job_ids <<< $1
log "job_ids=${job_ids[@]}"
job_cnt=${#job_ids[@]}
log "job_cnt=$job_cnt"

slots=(${2//,/ })
log "slots=${slots[@]}"
slot_cnt=${#slots[@]}
log "slot_cnt=$slot_cnt"

if [ $job_cnt -ne $slot_cnt ]; then
  out "Job and slot arrays has different sizes: $job_cnt!=$slot_cnt"
  exit 1
fi

users=(${3//,/ })
log "users=${users[@]}"

free_slots_array=(${4//,/ })
free_slots=0
for s in ${free_slots_array[@]}; do
  free_slots=$((free_slots + s))
done
log "free_slots: $free_slots"

total_slots=0
for s in ${slots[@]}; do
  total_slots=$((total_slots + s))
done
out "Total slots requested buy jobs: $total_slots"

total_slots=$((total_slots - free_slots))
if [ $total_slots -le 0 ]; then
  out "Do not scale up, new slots requested: $total_slots, already available: $free_slots"
  # get nodes with free slots
  #qstat -f | awk '/all.q/ {printf("%s %s",$1,$3)}' | 
fi

new_nodes_cnt=$((total_slots / SLOTS_ON_EXECD))
extra=$((total_slots - new_nodes_cnt * SLOTS_ON_EXECD))
log "extra=$extra"
if [ $extra -gt 0 ]; then
  new_nodes_cnt=$((new_nodes + 1))
fi

echo "Adding $new_nodes_cnt new nodes"

if false; then
  ret=0
else
  request_id=$(set -o pipefail; \
    $TORTUGA_ROOT/bin/add-nodes \
      --software-profile $SOFTWARE_PROFILE \
      --hardware-profile $HARDWARE_PROFILE \
      --count $new_nodes_cnt | \
    awk -F[ '{print $2}' | awk -F] '{print $1}')
  ret=$?
fi

if [ $ret -ne 0 ]; then
  out "Error: add-nodes returned: $ret"
  exit 1
fi

#job_ids_with_data=()
paths_from_local=()
paths_from_shared=()
paths_to_local=()
paths_to_shared=()
for ((cnt=0; cnt<${#job_ids[@]}; ++cnt)) {
  job_id=${job_ids[$cnt]}
  user=${users[$cnt]}
#for job_id in ${job_ids[@]}; do
#  jarr=($(qstat -j $job_id | awk -F': ' '/hard resource_list|env_list/ {print $2}'))
  # expects soft resource list to be there (as summlies by qsub-wrapper.sh)
  jarr=($(set -o pipefail; qstat -j $job_id | awk -F': ' '/soft resource_list|env_list/ {print $2}'))
  if [ $? -ne 0 ]; then
    out "ERROR: from qstat for job id: $job_id"
    continue
  fi
  resource_list=${jarr[0]}
  env_list=${jarr[1]}
  resource_list_arr=(${resource_list//,/ })
  env_list_arr=(${env_list//,/ })
  qalter_params=
  qalter_add_hard=
  for hl in ${resource_list_arr[@]}; do
    if [[ $hl = "$LOCAL_PATH_COMPLEX"* ]]; then
#      path="${hl##*=}"
      qalter_params="$qalter_params -clears l_soft $LOCAL_PATH_COMPLEX"
      qalter_add_hard_key="-adds l_hard $LOCAL_PATH_COMPLEX"
      qalter_add_hard_val="${hl##*=}"
      path="${hl##*=\*}"
      path="${path%%\*}"
      t=${env_list#*SGE_DATA_IN_SRC_STORAGE=}
      t=${t%%,*}
      if [ "$t" == "HOME" ]; then
        lpath="$(eval echo "~$user")/$path"
      elif [ "$t" == "SCRATCH" ]; then
        lpath="$SCRATCH_ROOT/$path"
      else
        out "Unexpected type: $t"
      fi
      paths_from_local+=($lpath)
#      path_to="${path//\//_}"
      path_to=$SGE_LOCAL_STORAGE_ROOT/$user/$(echo $path | base64)
      paths_to_local+=($path_to)
#      job_ids_with_data+=($job_id)
      if [[ ! $env_list = *"SGE_DATA_IN"* ]]; then
        qalter_params="$qalter_params -adds v SGE_DATA_IN $path_to"
      fi
      break
    elif [[ $hl = "$SHARED_PATH_COMPLEX"* ]]; then
      qalter_params="$qalter_params -clears l_soft $SHARED_PATH_COMPLEX"
      qalter_add_hard_key="-adds l_hard $SHARED_PATH_COMPLEX"
      qalter_add_hard_val="${hl##*=}"
      path="${hl##*=\*}"
      path="${path%%\*}"
      t=${env_list#*SGE_DATA_IN_SRC_STORAGE=}
      t=${t%%,*}
      if [ "$t" == "HOME" ]; then
        lpath="$(eval echo "~$user")/$path"
      elif [ "$t" == "SCRATCH" ]; then
        lpath="$SCRATCH_ROOT/$path"
      else
        out "Unexpected type: $t"
      fi
      paths_from_shared+=($lpath)
      path_to=$SGE_SHARED_STORAGE_ROOT/$user/$(echo $path | base64)
      paths_to_shared+=($path_to)
#      job_ids_with_data+=($job_id)
      if [[ ! $env_list = *"SGE_DATA_IN"* ]]; then
        qalter_params="$qalter_params -adds v SGE_DATA_IN $path_to"
      fi
      break
    fi
  done
  for el in ${env_list_arr[@]}; do
    if [[ $el = "$SYNC_BACK_ENV_VAR="* ]]; then
      log "sync_back: $el"
      path="${el#*=}"
      path_from="${path%%:*}"
      if [ ! -z "$path_from" ]; then
        qalter_params="$qalter_params -adds v SGE_DATA_OUT $path_from"
        path_to="${path##*:}"
        if [[ $path_to = "HOME/"* ]]; then
          to="${path_to#HOME/}"
          path_to="HOME/$user/$to"
        elif [[ $path_to = "SCRATCH/"* ]]; then
          to="${path_to#SCRATCH/}"
          path_to="SCRATCH/$to"
        else
          out "HOME or SCRATCH specifier expected in $SYNC_BACK_ENV_VAR"
          path_to=
        fi
        if [ ! -z "$path_to" ]; then
          qalter_params="$qalter_params -adds v SGE_DATA_OUT_BACK $path_to"
        fi
      fi
      break
    fi
  done
  if [ ! -z "$qalter_add_hard_key" ]; then
    log "qalter $qalter_add_hard_key $qalter_add_hard_val $job_id"
    qalter -p 1000 $qalter_add_hard_key "$qalter_add_hard_val" $job_id
  fi
  if [ ! -z "$qalter_params" ]; then
    log "qalter $qalter_params $job_id"
    qalter $qalter_params $job_id
  fi
#done
}

#echo "job_ids_with_data=${job_ids_with_data[@]}"
log "paths_from_local=${paths_from_local[@]}"
log "paths_to_local=${paths_to_local[@]}"
log "paths_from_shared=${paths_from_shared[@]}"
log "paths_to_shared=${paths_to_shared[@]}"

# check if any nodes with shared storage type are available
# to accept data transfer
if [ ${#paths_to_shared[@]} -gt 0 ]; then
  nodes_with_shared=()
  for h in $(qconf -sel); do
    if qconf -se $h | grep $SHARED_PATH_BOOL_COMPLEX ; then
      nodes_with_shared+=(h)
    fi
  done
  out "Nodes with shared storage type available: ${nodes_with_shared[@]}"
  ssh_available=($(for i in $(seq 1 ${#nodes_with_shared[@]}); do echo 1; done))

# before bash 4.3
  upload_data "$(echo ${nodes_with_shared[@]})" \
              "$(echo ${ssh_available[@]})" \
              "$(echo ${paths_from_shared[@]})" \
              "$(echo ${paths_to_shared[@]})"
#  upload_data nodes_with_shared ssh_available paths_from_shared paths_to_shared
else
  out "No nodes with shared storage type available"
fi

out "Waiting for nodes to boot..."
while get-node-requests -r $request_id | fgrep -q pending ; do
  progress
  sleep 1
done

new_nodes=($(get-node-requests -r $request_id | tail -n +2))
out "New nodes added: ${new_nodes[@]}"
ssh_available=($(for i in $(seq 1 ${#new_nodes[@]}); do echo 0; done))
upload_data "$(echo ${new_nodes[@]})" \
            "$(echo ${ssh_available[@]})" \
            "$(echo ${paths_from_shared[@]} ${paths_from_local[@]})" \
            "$(echo ${paths_to_shared[@]} ${paths_to_local[@]})"
#upload_data new_nodes ssh_available paths_from_local paths_to_local

# prepare load sensors and prolog/epilog
sed "s|%%SGE_STORAGE_ROOT%%|$SGE_LOCAL_STORAGE_ROOT|; \
     s|%%SGE_COMPLEX_NAME%%|$LOCAL_PATH_COMPLEX|; \
     s|%%SGE_BOOL_COMPLEX_NAME%%|$LOCAL_PATH_BOOL_COMPLEX|; \
     s|%%DEPTH%%|1|" \
     $SCRIPT_DIR/load-sensor.sh > /tmp/lls.sh
chmod a+x /tmp/lls.sh

sed "s|%%SGE_STORAGE_ROOT%%|$SCRATCH_ROOT|; \
     s|%%SGE_COMPLEX_NAME%%|$SHARED_PATH_COMPLEX|; \
     s|%%SGE_BOOL_COMPLEX_NAME%%|$SHARED_PATH_BOOL_COMPLEX|; \
     s|%%DEPTH%%|1|" $SCRIPT_DIR/load-sensor.sh > /tmp/sls.sh
chmod a+x /tmp/sls.sh

sed "s|%%RSYNCD_HOST%%|$RSYNCD_HOST|; \
     s|%%SCRATCH_ROOT%%|$SCRATCH_ROOT|" \
     $SCRIPT_DIR/epilog.sh > /tmp/epilog.sh

chmod a+x /tmp/epilog.sh
sed "s|%%RSYNCD_HOST%%|$RSYNCD_HOST|; \
     s|%%SCRATCH_ROOT%%|$SCRATCH_ROOT|" \
     $SCRIPT_DIR/prolog.sh > /tmp/prolog.sh
chmod a+x /tmp/prolog.sh

# wait for UGE become available on compute nodes
# install load sensor
max_cnt=100
max_err_cnt=120
#max_err_cnt=$((10 * new_nodes_total))
err_cnt=0
new_nodes_copy=("${new_nodes[@]}")
out "Waiting for UGE become available on nodes: ${new_nodes[@]}"
for((cnt=0;cnt<max_cnt;++cnt)) { 
  tmp=()
  for node in ${new_nodes_copy[@]}; do
    log "Waiting for UGE on $node"
    node_short=${node%%.*}
  #  for((i=0;i<new_nodes_total;++i)); do
#    if [ -z "$(qstat -f | grep $node)" ]; then
    if ! qstat -f | fgrep -q $node_short ; then
      log "No execd on $node yet"
      err_cnt=$((err_cnt + 1))
      if [ $err_cnt -gt $max_err_cnt ]; then
        out "Too many attempts waiting for UGE become ready on $node"
        continue
      fi
      tmp+=($node)
      continue
    fi
#    if [ -z "$(qstat -f -qs u | grep $node)" ]; then
    if ! qstat -f -qs u | fgrep -q $node_short ; then
      out "Node $node available"
      # copy load sensor and epilog
      sudo su - sge -c "scp -o StrictHostKeyChecking=no /tmp/lls.sh /tmp/sls.sh /tmp/epilog.sh /tmp/prolog.sh sge@${node}:${LOAD_SENSOR_DIR}"
      ret=$?
      if [ $ret -ne 0 ]; then
        out "Error installing load sensor, prolog or epilog: scp exit code: $ret"
      fi
      hf=/tmp/$node
      qconf -sconf $node > $hf
      echo "load_sensor $LOAD_SENSOR_DIR/lls.sh,$LOAD_SENSOR_DIR/sls.sh" >> $hf
      echo "prolog $LOAD_SENSOR_DIR/prolog.sh" >> $hf
      echo "epilog $LOAD_SENSOR_DIR/epilog.sh" >> $hf
      # temporary change load sensor period to short value
      echo "load_report_time 5" >> $hf
      qconf -Mconf $hf
      # add epilog
#      qconf -mattr queue epilog $LOAD_SENSOR_DIR/epilog.sh all.q
#      qconf -mattr queue prolog $LOAD_SENSOR_DIR/prolog.sh all.q
    else
      progress
      log "UGE on $node is still in 'u' state"
      tmp+=($node)
    fi
  done
  if [ ${#tmp[@]} -eq 0 ]; then
    out "All UGE new compute nodes ready"
    break
  fi
  new_nodes_copy=(${tmp[@]})
  if [ $err_cnt -gt $max_err_cnt ]; then
    out "Too many attempts waiting for UGE become ready on new nodes"
    break
  fi
  sleep 1
}

# wait default load sensor reporting interval
log "Waiting default load report interval"
sleep 40
# change back to default by removing it
for node in ${new_nodes[@]}; do
  hf=/tmp/$node
  qconf -sconf $node > $hf
  sed -i '/^load_report_time[ \t]*5.*/ d' $hf
  qconf -Mconf $hf
done

log "End"
