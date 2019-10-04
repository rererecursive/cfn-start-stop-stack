# Changes
- Allow credentials in environment variables to be used
- Remove unnecessary (duplicate) API calls in visit_stacks()
- Don't generate new credentials for every collected resource
- Look up a resource's state just before
- Restructure the resource handlers to be separate from the resources
- Separate the process of health checking from that of starting/stopping a resource
- Remove the '--wait-async' flag as its functioanlity is the default (and only) behaviour. It was buggy anyway and only applied to some resources
- Make the dry_run functionality fine-grained

TODO
----
- Make the dry_run functionality fine-grained
- Provide the ability to dump/load the stack contents to a file (quicker development):
    --to-file <>    --from-file <>
- Why on earth are we exporting environment variables to pass information between files?
- Throw an error if dependencies and --skip-wait are specified, as they are mutually exclusive.
- Waiting for a resource should not be done inside the handler, but inside by the outer 'controller' loop for the specific batch

- Use the default resource priorities to assist us in construction the DAG.
Note that the default priorities is one particular order, but the config is a way to MODIFY that order.

1. Collect all CloudFormation resources.
2. Organise the resources into groups based on their default priorities
- Process the dependencies in config.yml:
  - Perform basic YAML validation
  - Check that the resources point to resources in the stack
  #- Mark each item in [list 1] as "start" to indicate the starting positions in the graph

- For each resource in the dependencies list,
  (The config is valid here)
  - If it has dependencies, add its name to each of the dependencies so that the latter is aware of what depends on it

# Begin "cycle detection", involving a dry-run execution
# This should be modified to run over resources that have dependencies
- For each batch,
  - For each resource,
    - If it is DEPENDED_ON_BY another resource, see if we can start that resource too
    - Follow the above recursively, marking each as 'visited'
    - If we find at any stage that the item is 'visited'

- For each batch,
  - Initialise the state of this batch (count started and unstarted resources)
  - While True:
    - If started == len(batch), skip
    - For each resource,
      - If it's started, skip it.
      - If it has a DEPENDS_ON, try to start its dependencies.
        - Starting involves running start(is_dependency=True) and setting it to INITIALISING. This requires modifying the start() function to allow failure if its dependencies are not RUNNING.
      - If not-started AND all-if-any of its dependencies started:
        - Start the resource
        - Update the state of the resource

    - Sleep for a period
    - Update the state of the resources in the batch
--
We need to have the start() function modified so that an "interdependency" (i.e. vertices in the graph that are not its boundaries) resource may be permitted to fail. In other words, a resource that has dependencies that have not started is allowed to fail to start. This puts the resource into the ATTEMPTED state.

---

Each resource goes through a phase of state transitions:
  - Start
  - HealthCheck
  - PostStart

Likewise, a *group* of resources go through the same phase.
