defmodule Bylaw.Credo.DocumentationTest do
  use ExUnit.Case, async: true

  @section_order ["Examples", "Options", "Usage", "Notes"]

  test "every Credo check documents examples without unsupported sections" do
    for module <- check_modules() do
      source =
        module
        |> source_path()
        |> File.read!()

      doc = moduledoc(source)
      sections = section_names(doc)

      assert "Examples" in sections, "#{inspect(module)} is missing an Examples section"
      assert String.contains?(doc, "Avoid:"), "#{inspect(module)} is missing an Avoid example"
      assert String.contains?(doc, "Prefer:"), "#{inspect(module)} is missing a Prefer example"

      assert has_rationale_after_prefer?(doc),
             "#{inspect(module)} is missing rationale after Prefer"

      assert summary_paragraph_count(doc) == 1,
             "#{inspect(module)} has rationale before its Examples section"

      refute "Why" in sections, "#{inspect(module)} should keep rationale under Prefer"
      refute Regex.match?(~r/^\s*Why:/m, doc), "#{inspect(module)} should not label rationale"
      refute Regex.match?(~r/static (?:AST|HEEx token) analysis/, doc)

      assert Enum.take(sections, 3) == Enum.take(@section_order, 3),
             "#{inspect(module)} should start with Examples, Options, and Usage sections"

      assert Enum.all?(sections, &(&1 in @section_order)),
             "#{inspect(module)} has an unsupported documentation section"
    end
  end

  defp check_modules do
    {:ok, modules} = :application.get_key(:bylaw_credo, :modules)

    Enum.filter(modules, fn module ->
      module
      |> Atom.to_string()
      |> String.starts_with?("Elixir.Bylaw.Credo.Check.")
    end)
  end

  defp source_path(module), do: module.module_info(:compile)[:source]

  defp moduledoc(source) do
    {:ok, ast} = Code.string_to_quoted(source)

    {_ast, moduledoc} =
      Macro.prewalk(ast, nil, fn
        {:@, _attribute_meta, [{:moduledoc, _doc_meta, [doc]}]} = node, _acc
        when is_binary(doc) ->
          {node, doc}

        node, acc ->
          {node, acc}
      end)

    moduledoc
  end

  defp section_names(moduledoc) do
    for [section] <- Regex.scan(~r/^##+ ([^\n]+)$/m, moduledoc, capture: :all_but_first),
        do: section
  end

  defp has_rationale_after_prefer?(moduledoc) do
    examples =
      moduledoc
      |> String.split("## Examples\n")
      |> Enum.at(-1)

    examples =
      examples
      |> String.split(~r/^## /m)
      |> Enum.at(0)

    examples
    |> String.split("Prefer:")
    |> List.last()
    |> String.split("\n")
    |> Enum.any?(&Regex.match?(~r/^[A-Za-z]/, &1))
  end

  defp summary_paragraph_count(moduledoc) do
    moduledoc
    |> String.split("## Examples\n")
    |> List.first()
    |> String.split(~r/\n\s*\n/)
    |> Enum.count(&(String.trim(&1) != ""))
  end
end
