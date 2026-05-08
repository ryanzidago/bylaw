defmodule Bylaw.Ecto.Schema do
  @moduledoc """
  Reflection helpers for compiled Ecto schema modules.

  These helpers intentionally inspect compiled modules instead of source code.
  Projects commonly wrap `use Ecto.Schema` in their own macros, so source-based
  detection would miss valid schemas.
  """

  @typedoc """
  Compiled schema metadata needed by database checks.
  """
  @type info :: %{
          module: module(),
          source: String.t(),
          prefix: String.t() | nil,
          fields: list(atom()),
          associations: list(atom()),
          field_sources: %{String.t() => atom()}
        }

  @doc """
  Returns compiled Ecto schema modules for an OTP application.
  """
  @spec modules(otp_app :: atom()) :: list(module())
  def modules(otp_app) when is_atom(otp_app) do
    otp_app
    |> application_modules()
    |> Enum.filter(&ecto_schema?/1)
    |> Enum.sort()
  end

  @doc """
  Returns true when `module` exports Ecto schema reflection functions.
  """
  @spec ecto_schema?(module :: module()) :: boolean()
  def ecto_schema?(module) when is_atom(module) and not is_nil(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :__schema__, 1) and
      function_exported?(module, :__schema__, 2) and
      function_exported?(module, :__changeset__, 0)
  end

  @doc """
  Returns compiled schema metadata.
  """
  @spec info(module :: module()) :: info()
  def info(module) when is_atom(module) do
    fields = module.__schema__(:fields)

    %{
      module: module,
      source: module.__schema__(:source),
      prefix: module.__schema__(:prefix),
      fields: fields,
      associations: module.__schema__(:associations),
      field_sources: field_sources(module, fields)
    }
  end

  defp application_modules(otp_app) do
    case :application.get_key(otp_app, :modules) do
      {:ok, modules} -> modules
      :undefined -> []
    end
  end

  defp field_sources(module, fields) do
    Map.new(fields, fn field ->
      {field_source(module.__schema__(:field_source, field)), field}
    end)
  end

  defp field_source(source) when is_atom(source), do: Atom.to_string(source)
  defp field_source(source), do: source
end
