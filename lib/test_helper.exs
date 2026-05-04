ExUnit.configure(exclude: [postgres: true])
ExUnit.start()

Application.ensure_all_started(:credo)
