defmodule Bylaw.Contract.FormatterCompiledSource do
  @moduledoc false
  require Mix.Compilers.Elixir
  alias Bylaw.Contract.FormatterDiffScope

  @doc false
  @spec validate(root :: String.t(), head :: String.t(), selected :: MapSet.t()) ::
          :ok | {:error, term()}
  def validate(root, head, selected) do
    manifest = Path.join(Mix.Project.manifest_path(), "compile.elixir")
    {modules, sources} = Mix.Compilers.Elixir.read_manifest(manifest)

    selected
    |> Enum.map(&elem(&1, 0))
    |> Enum.uniq()
    |> Enum.reduce_while(:ok, fn module, :ok ->
      case validate_module(module, modules, sources, root, head) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  rescue
    error -> {:error, {:compiled_source_unavailable, Exception.message(error)}}
  end

  defp validate_module(module, modules, sources, root, head) do
    with {:ok, Mix.Compilers.Elixir.module(sources: paths)} <- Map.fetch(modules, module),
         :ok <- validate_paths(module, paths, sources, root, head),
         {:module, ^module} <- Code.ensure_loaded(module),
         {^module, binary, _} <- :code.get_object_code(module),
         {:ok, {^module, md5}} <- :beam_lib.md5(binary),
         true <- module.module_info(:md5) == md5 do
      :ok
    else
      {:error, _} = error -> error
      false -> {:error, {:loaded_beam_mismatch, module}}
      _ -> {:error, {:compiled_source_unavailable, module}}
    end
  end

  defp validate_paths(module, paths, sources, root, head) do
    Enum.reduce_while(paths, :ok, fn path, :ok ->
      relative = Path.relative_to(Path.expand(path), root)

      with {:ok, Mix.Compilers.Elixir.source(digest: digest, modules: compiled_modules)} <-
             Map.fetch(sources, path),
           true <- module in compiled_modules,
           {:ok, committed} <-
             FormatterDiffScope.git(root, ["show", head <> ":" <> relative], false),
           {:ok, current} <- File.read(path),
           true <- current == committed and digest in digests(committed) do
        {:cont, :ok}
      else
        _ -> {:halt, {:error, {:compiled_source_mismatch, module, path}}}
      end
    end)
  end

  defp digests(source) do
    [:blake2b, :blake2s, :md5]
    |> Enum.flat_map(fn algorithm ->
      try do
        [:crypto.hash(algorithm, source)]
      rescue
        _ -> []
      end
    end)
  end
end
