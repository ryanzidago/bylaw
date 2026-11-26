defmodule Bylaw.Credo.Check.Ecto.UUIDFieldTypes do
  @moduledoc """
  Requires explicit `Ecto.UUID.t()` types for UUID fields in schema `t/0` declarations.

  ## Examples

  Avoid:

      @type t :: %__MODULE__{id: String.t(), parent_id: binary()}

  Prefer:

      @type t :: %__MODULE__{id: Ecto.UUID.t(), parent_id: Ecto.UUID.t() | nil}

  UUID fields declared with `:binary_id` or `Ecto.UUID` need a semantic UUID type;
  `String.t()`, `binary()`, `any()`, `term()` and local aliases hide that contract.
  `Ecto.UUID` aliases and unions with `nil` are accepted. String fields, including
  natural codes and external service IDs, are unaffected.

  ## Options

  No check-specific options. Configure it with an empty option list.

  ## Usage

  Add `{Bylaw.Credo.Check.Ecto.UUIDFieldTypes, []}` to the Credo checks list.

  ## Notes

  This check reads explicit `field`, `belongs_to`, `@primary_key` and
  `@foreign_key_type` declarations, plus native `use Ecto.Schema` defaults.
  It checks `schema` and `embedded_schema` blocks, including types declared first.
  It does not expand custom schema wrappers. Run `Bylaw.Credo.StructTypes.validate/3`
  with `uuid_fields: true` after compilation to cover inherited defaults and fields.
  Use `FullySpecifiedStructTypes` and the compiled audit for missing declarations.
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:database, :architecture],
    explanations: [check: @moduledoc]

  alias Bylaw.Credo.SourceTypes
  alias Bylaw.Credo.UUIDSchema

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    meta = IssueMeta.for(source_file, params)

    source_file
    |> Credo.SourceFile.ast()
    |> SourceTypes.from_ast(source_file.filename)
    |> Enum.flat_map(&module_issues(&1, meta))
    |> Enum.sort_by(& &1.line_no)
  end

  defp module_issues({module, entry}, meta) do
    fields = UUIDSchema.static_fields(entry, module)

    entry
    |> UUIDSchema.invalid_fields(module, fields)
    |> Enum.flat_map(fn {line, invalid} ->
      Enum.map(invalid, &field_issue(&1, line, meta))
    end)
  end

  defp field_issue(field, line, meta) do
    format_issue(meta,
      line_no: line,
      trigger: Atom.to_string(field),
      message: "Type UUID field `#{field}` explicitly as Ecto.UUID.t() or Ecto.UUID.t() | nil."
    )
  end
end
