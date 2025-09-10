# Seventh State PauseR

The Seventh State PauseR Plugin introduces pause_minority equivalent behaviour tailored for Khepri in RabbitMQ.
It detects when the local node is in a minority partition and enforces a pause mode by:

- Suspending all listeners
- Closing all existing client connections

This guide explains how to install, configure, and use the plugin.

**Note**: This plugin only works when RabbitMQ is running with Khepri enabled. It has no effect if Khepri is disabled.

## Requirements

- RabbitMQ ≥ 4.1.0 (tested with RabbitMQ 4.1.2) with **Khepri enabled**.  
  Install RabbitMQ with a compatible Erlang version as listed at:  
  https://www.rabbitmq.com/docs/which-erlang

- RabbitMQ must be configured with:  
  `cluster_partition_handling = pause_minority`

## Installation

1. Obtain the Plugin  
   The plugin must be compatible with your RabbitMQ and Erlang versions.  
   Download the correct plugin build for your environment.

2. Locate the RabbitMQ Plugin Directory  
   You can find the plugin directory by running:  
   `rabbitmq-plugins directories`  
   Example output:  
   `Plugin archives directory: /usr/lib/rabbitmq/plugins:/usr/lib/rabbitmq/lib/rabbitmq_server-4.1.2/plugins`

3. Add the Plugin  
   Copy the plugin into the plugins directory:  
   `cp seventh_state_pauser.ez /usr/lib/rabbitmq/lib/rabbitmq_server-<version>/plugins/`

4. Enable the Plugin  
   `rabbitmq-plugins enable seventh_state_pauser`

5. Restart RabbitMQ  
   `systemctl restart rabbitmq-server`

Make sure all cluster nodes have the plugin installed and enabled.

## Configuration

The plugin works automatically based on RabbitMQ’s native configuration.

The plugin uses this setting to determine how to react and manage cluster recovery.

The interval between checks can be configured through:

`seven_pauser.check_interval_seconds = 5`

The default value is 5 seconds, which offers a balance between resource usage and efficiency of detection.
A lower value will detect partitions quicker at the cost of an increased resource usage.

## Default Kherpi Behaviour

When a node is in a minority partition:

- Existing connections remain open
- New connections are accepted
- Local publish/consume on **pre-declared classic queues** continues (producer and consumer on the same node)
- Queue declarations (any type) are rejected

## Plugin Behaviour

- On startup, the plugin automatically starts alongside the RabbitMQ cluster, operating in line with the configured cluster_partition_handling.
- Every interval (default 3 seconds), the plugin checks whether the local node is in a minority partition.
- If in minority:
   - Suspend all non-management listeners and prevents new client connections
   - Close all existing client connections
- If recovered to majority:
   - Resume all listeners
   - Allow new client connections
- Management listeners (e.g., HTTP API, Management UI) still remain available.

## Development

You can choose to build and test the plugin using either:

* **Docker Compose** (to avoid local environment issues), or
* **Your local setup** (if you already have compatible Erlang/Elixir installed).

## Build and Test Locally (Without Docker)

If you prefer to work locally, make sure you have:

* **Erlang/OTP 26.2**
* **Elixir 1.14.5**

These versions are compatible with most RabbitMQ versions: from `3.12.10` to `4.x`.

No need to install RabbitMQ — this project can start a broker for you.

## Common Makefile Commands

```bash
gmake tests                          # Run all tests (logs appear in ./logs)
gmake run-broker                     # Start RabbitMQ broker with an interactive Erlang shell
gmake start-cluster                  # Start a 3-node RabbitMQ cluster (customise with NODES=5)
gmake stop-cluster                   # Stop the running cluster
gmake dist DIST_AS_EZS=1             # Create a .ez plugin file (output in ./plugins)
gmake ct-a_test_suite                # Run a test suite
gmake ct-a_test_suite t="group"      # Run a test group inside the suite
gmake ct-a_test_suite t="group:case" # Run a specific test case
```

> Test files are located in the `test/` directory.
> If you add new plugin functionality, you should add corresponding tests there.

> To install and test your `.ez` plugin on any RabbitMQ node, follow the official plugin installation guide:
> [https://www.rabbitmq.com/plugins.html](https://www.rabbitmq.com/plugins.html)

> For more useful commands and development guidelines, refer to the official RabbitMQ contribution guide:
> [https://github.com/rabbitmq/rabbitmq-server/blob/main/CONTRIBUTING.md](https://github.com/rabbitmq/rabbitmq-server/blob/main/CONTRIBUTING.md)

## Build and Test with Docker Compose

1. **Build the Docker image:**

   ```bash
   docker compose -f build/docker-compose.yml build --no-cache
   ```

2. **Run tests and build the plugin:**

   ```bash
   docker compose -f build/docker-compose.yml run --rm test-and-build make tests
   docker compose -f build/docker-compose.yml run --rm test-and-build make dist DIST_AS_EZS=1
   ```

   > If you see a `flock`-related error like:
   > `flock: can't open 'sbin.lock': No such file or directory`
   > just re-run the command — it’s usually transient.

3. **Test logs and build artifacts** will be available in your project root directory after the run.

   * `logs/` – contains test logs.
   * `plugins/` – contains the generated `.ez` plugin files.

> This approach avoids local dependency/version issues.

