require Logger
# Match guides/configuration.md recommendation: no implicit retries in tests.
Application.put_env(:jido_action, :default_max_retries, 0)

# Prepare modules for Mimic
Enum.each(
  [
    :telemetry,
    System,
    Req,
    Tentacat.Issues
  ],
  &Mimic.copy/1
)

# Suite requires debug level for all tests
Logger.configure(level: :debug)

ExUnit.start()

ExUnit.configure(capture_log: true, exclude: [:skip])
