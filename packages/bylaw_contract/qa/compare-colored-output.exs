# Compare rendering of zero-call snapshots, not test coverage or performance.
app = System.fetch_env!("BYLAW_COLOR_APP") |> String.to_existing_atom()
output = System.fetch_env!("BYLAW_COLOR_OUTPUT")
File.mkdir_p!(output)
source = File.read!(System.fetch_env!("BYLAW_COLOR_BASELINE"))

Code.compile_string(
  String.replace(
    source,
    "defmodule Bylaw.Contract.Report do",
    "defmodule Bylaw.Contract.ColorQABaselineReport do"
  )
)

{:ok, tracer} = Bylaw.Contract.start(Application.spec(app, :modules))
coverage = Bylaw.Contract.stop(tracer)
if Map.get(coverage, :status) == :incomplete, do: raise("snapshot observation incomplete")

render = fn renderer ->
  {:ok, io} = StringIO.open("")
  renderer.(io)
  {_, text} = StringIO.contents(io)
  StringIO.close(io)
  text
end

baseline = render.(&Bylaw.Contract.ColorQABaselineReport.print(coverage, &1))
plain = render.(&Bylaw.Contract.print_report(coverage, &1, colors: false))
colored = render.(&Bylaw.Contract.print_report(coverage, &1, colors: true))
stripped = String.replace(colored, ~r/\e\[[0-9;]*m/, "")
if plain != baseline or stripped != baseline, do: raise("report text changed")
if String.contains?(plain, "\e["), do: raise("ANSI leaked into plain output")
if not String.contains?(colored, "\e[31m✗\e[0m"), do: raise("no colored findings")
File.write!(Path.join(output, "plain.txt"), plain)
File.write!(Path.join(output, "colored.ansi"), colored)

result = %{
  app: app,
  modules: length(Application.spec(app, :modules)),
  snapshot: "complete, zero-call observation; rendering comparison only",
  plain_bytes: byte_size(plain),
  colored_bytes: byte_size(colored),
  findings: length(Regex.scan(~r/✗/, plain)),
  baseline_equal: true,
  stripped_equal: true,
  sha256: Base.encode16(:crypto.hash(:sha256, plain), case: :lower)
}

File.write!(
  Path.join(output, "result.txt"),
  inspect(result, pretty: true, limit: :infinity) <> "\n"
)

IO.inspect(result, pretty: true)
