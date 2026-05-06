import Config

config :bylaw_postgres, ecto_repos: [Bylaw.Db.Postgres.TestRepo]

config :bylaw_postgres, Bylaw.Db.Postgres.TestRepo,
  url: System.get_env("BYLAW_POSTGRES_URL", "postgres://localhost:5432/bylaw_test"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  log: false
