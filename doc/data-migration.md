# v1 design considerations.

v1 implementation is based on configuration script used by the administrator for initial preparation and bash script managing cloud bursting and data transfers supplied with appropriate parameters from external event trigger.


## Possible trigger sources

- Unisight rule engine
- systemd timers
- cron job
- script started by administrator

## Unisight rule

- Unisight polling rule is created with following:
    conditions: job state = qw, job slots  > 1
    parameters passed to external script invocation: job_ids, job_slots, job_users, job_queues, queue_available_slots, queue_names
- Bash script invocation is triggered by Unisight rule engine polling event

## Configuration script actions 

- add puppet module for user ids management (for recreating all local users on cloud nodes)
- add puppet module for user's ssh key management ()
- defines cloud node local data storage root directory
- defines shared between all cloud nodes data storage nfs mount point
- add puppet module for provisioning nfs mount
- create UGE complex to be requested by job submission which value contains source file or directory path to be transferred to the cloud node
- create load sensor script responsible to be used on cloud node to provide values for the above complex
- defines cloud node type

## Cloud bursting and data migration script

- calculates total number of slots required by all waiting jobs
- calculates number of new nodes to be created on the cloud
- uses tortuga to request creation of the cloud nodes 
- while cound nodes provisioning is in progress use source data pathes from the complex for the jobs which have it requested to initiate data sequential or parallel transfers to the nodes with rsync via ssh whenever sshd becomes available on receiving side and possibly create various metadata inside the destination directories with ttl, etc.
- install epilog script on cloud nodes taking care of transferring data back from cloud node
- alter jobs submitted with request to transfer data back with new environment variables describing source and destination
- alter jobs submitted with request to transfer with new environment variable describing job's data location on cloud node
- install load sensor when execd become available on cloud nodes (load sensor will make jobs requested complex available triggering job submission to the node with expected data)

## Cloud unbursting

- use Unisight rule to delete idle nodes


