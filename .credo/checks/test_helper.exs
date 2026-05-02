"../../lib/test_helper.exs"
|> Path.expand(__DIR__)
|> Code.require_file()

Application.ensure_all_started(:credo)

__DIR__
|> Path.join("*.ex")
|> Path.expand()
|> Path.wildcard()
|> Enum.each(&Code.require_file/1)
