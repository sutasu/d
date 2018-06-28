# Data migration project

## Precequisites
UGE cluster with Tortuga on AWS with at least one compute node.

## Steps to try

- run configuration script as `root`:

```
# ./configure.sh
```

It will install `qsub-wrapper.sh` and `scale-up.sh` scripts to Tortuga binary directory.

- create input data directory for jobs:

```
$ mkdir -p ~/input1; touch ~/input1/infile1
$ mkdir -p ~/input2; touch ~/input2/infile2
```

- submit 2 jobs with qsub wrapper script (see `qsub-wrapper.sh -h` for details) from regular UGE user (`centos`):

```
$ qsub-wrapper.sh -src HOME/input1 -dest LOCAL -sync-back /home/$USER/out1:HOME/out1 -j y test/job.sh infile1 newfile1
$ qsub-wrapper.sh -src HOME/input2 -dest LOCAL -sync-back /home/$USER/out2:HOME/out2 -j y test/job.sh infile2 newfile2
```

For each job input file will be transferred to the remote cluster node (to be created by `scale-up.sh` script) and new file will be created by job script in the same outout directory. Upon job completion both file will be transferred back to the local cluster.

- check that jobs are in pending state and get job ids (`qstat -f`)

- run manually cluster scale script as `root` user (could be invoked form Unisight rule engine or another periodic or event based trigger). For 2 jobs started above by `centos` user following invocation should be used:

```
# scale-up.sh <job_id>,<job_id> 1,1 centos,centos 0,0 2,2 all.q
```

This script will provision and configure new node[s] as well as transfer input data expected by jobs to the remote cluster nodes.

- wait for completion of the jobs

- check output of the jobs in submitter (`centos`) home directory:

```
$ ls ~/out1
infile1  job.sh.o<job_id>  newfile1
$ ls ~/out2
infile2  job.sh.o<job_id>  newfile2
```

- clean output and submit one of the jobs again:

```
$ rm -rf ~/out1
$ qsub-wrapper.sh -src HOME/input1 -dest LOCAL -sync-back /home/$USER/out1:HOME/out1 -j y test/job.sh infile1 newfile99
```
With no other pending jobs the new job will start on the node with data (`infile1`) already present.

- observe outout:

```
$ ls ~/out1
infile1  job.sh.o<job_id>  newfile99
```
