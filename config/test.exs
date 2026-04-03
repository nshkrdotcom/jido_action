import Config

log_level = System.get_env("LOG_LEVEL", "warning") |> String.to_existing_atom()

config :logger,
  level: log_level
