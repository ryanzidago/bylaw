Code.require_file("overhead-result.exs", __DIR__)
[input, "defaults"] = System.argv()
result = input |> File.read!() |> :erlang.binary_to_term()

IO.puts(
  JSON.encode!(%{
    test_identities:
      Enum.map(result.test_identities, fn {module, name, line} ->
        [inspect(module), to_string(name), line]
      end),
    report_sha256: result.report_sha256
  })
)
