defmodule Bylaw.Contract.Report do
  @moduledoc """
  The properties found in the observed modules and which of them were observed.

  The printed report lists only actionable findings: `:missed` properties.
  `:unassessable` properties stay in `properties` and are never reported as
  missed.
  """

  alias Bylaw.Contract.Property

  @type t :: %__MODULE__{
          properties: list(Property.t()),
          warnings: list(String.t())
        }

  @type summary :: %{
          properties: non_neg_integer(),
          observed: non_neg_integer(),
          missed: non_neg_integer(),
          unassessable: non_neg_integer()
        }

  defstruct properties: [], warnings: []

  @resolution "Each gap is one of: a missing test, a spec or guard wider than the code, or dead code. " <>
                "Resolve it: add a test, narrow the spec or guard, or delete the unreachable code.\n"

  @kind_order [
    :clause,
    :guard_rejection,
    :argument_class,
    :argument_boundary,
    :return_alternative
  ]

  @doc "Returns the properties that no test exercised."
  @spec missed(report :: t()) :: list(Property.t())
  def missed(%__MODULE__{properties: properties}),
    do: Enum.filter(properties, &(&1.status == :missed))

  @doc "Counts properties by status."
  @spec summary(report :: t()) :: summary()
  def summary(%__MODULE__{properties: properties}) do
    counts = Enum.frequencies_by(properties, & &1.status)

    %{
      properties: Enum.count(properties),
      observed: Map.get(counts, :observed, 0),
      missed: Map.get(counts, :missed, 0),
      unassessable: Map.get(counts, :unassessable, 0)
    }
  end

  @doc """
  Formats the missed properties, or returns an empty string when there are none.

  Options: `:colors` (default `IO.ANSI.enabled?/0`).
  """
  @spec format(report :: t(), options :: list({:colors, boolean()})) :: String.t()
  def format(%__MODULE__{} = report, options \\ []) do
    colors? = Keyword.get(options, :colors, IO.ANSI.enabled?())

    case missed(report) do
      [] ->
        ""

      missed ->
        groups =
          missed
          |> Enum.sort_by(&sort_key/1)
          |> Enum.group_by(&{&1.module, &1.function, &1.arity})
          |> Enum.sort_by(fn {_function, [first | _rest]} ->
            {first.module, first.file, first.line}
          end)

        body =
          Enum.map_join(groups, "\n", fn {{module, function, arity}, properties} ->
            heading = "#{inspect(module)}.#{function}/#{arity}"
            findings = Enum.map_join(properties, "\n", &finding(&1, colors?))
            "#{heading}\n#{findings}\n"
          end)

        "Bylaw.Contract gaps\n\n" <> body <> @resolution
    end
  end

  @doc "Prints the formatted report to a device."
  @spec print(report :: t(), device :: IO.device(), options :: list({:colors, boolean()})) :: :ok
  def print(%__MODULE__{} = report, device \\ :stdio, options \\ []) do
    case format(report, options) do
      "" -> :ok
      output -> IO.puts(device, output)
    end
  end

  defp sort_key(property) do
    {Enum.find_index(@kind_order, &(&1 == property.kind)), property.clause || 0,
     property.argument || 0, property.label || ""}
  end

  defp finding(property, colors?) do
    location = "#{relative(property.file)}:#{property.line}"

    [
      paint("    ✗ ", :red, colors?) <> paint(location, :cyan, colors?),
      "      #{title(property)}",
      "",
      indent(source(property), colors?),
      detail(property)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp title(%{kind: :clause, clause: clause}),
    do: "Untested clause - no test selected clause #{clause}:"

  defp title(%{kind: :guard_rejection, clause: clause}),
    do: "Untested guard - no test made the guard of clause #{clause} reject a call:"

  defp title(%{kind: :argument_class}),
    do: "Untested argument alternative - no test passed this declared alternative:"

  defp title(%{kind: :argument_boundary}),
    do: "Untested argument boundary - no test passed this declared boundary value:"

  defp title(%{kind: :return_alternative}),
    do: "Untested return alternative - no test returned this declared alternative:"

  defp detail(%{kind: :clause, clause: clause}), do: "\n      clause #{clause}"
  defp detail(%{kind: :guard_rejection, clause: clause}), do: "\n      guard of clause #{clause}"

  defp detail(%{kind: :argument_class} = property),
    do: "\n      argument #{property.argument}: #{property.label}"

  defp detail(%{kind: :argument_boundary} = property),
    do: "\n      argument #{property.argument} boundary: #{property.label}"

  defp detail(%{kind: :return_alternative} = property), do: "\n      return: #{property.label}"

  defp source(%{kind: kind, source: source}) when kind not in [:clause, :guard_rejection],
    do: source || ""

  defp source(%{file: file, line: line}), do: source_line(file, line)

  defp source_line(file, line) when is_binary(file) and is_integer(line) do
    case File.read(file) do
      {:ok, content} -> content |> String.split("\n") |> Enum.at(line - 1, "") |> String.trim()
      {:error, _reason} -> ""
    end
  end

  defp source_line(_file, _line), do: ""

  defp indent(text, colors?) do
    text
    |> String.split("\n")
    |> Enum.map_join("\n", &paint("      " <> &1, :faint, colors?))
  end

  defp relative(nil), do: "unknown"
  defp relative(file), do: Path.relative_to_cwd(file)

  defp paint(text, _color, false), do: text
  defp paint(text, :red, true), do: IO.ANSI.red() <> text <> IO.ANSI.reset()
  defp paint(text, :cyan, true), do: IO.ANSI.cyan() <> text <> IO.ANSI.reset()
  defp paint(text, :faint, true), do: IO.ANSI.faint() <> text <> IO.ANSI.reset()
end
