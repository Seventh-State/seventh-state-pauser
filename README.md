# Seventh State Khepri Pause-Minority

The Seventh State Khepri Pause-Minority plugin introduces `pause_minority` equivalent behaviour tailored for Khepri in RabbitMQ.

It detects when the local node is part of a minority partition and enforces a safe degraded mode by:

- Suspending all listeners (excluding the management listeners)
- Closing all existing client connections

## Getting Started

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

