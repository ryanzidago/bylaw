defmodule Bylaw.Credo.Check.PhoenixLiveView.RequireExplicitConnectionStateHandlingInMount do
  @moduledoc """
  Require LiveView `mount/3` clauses to explicitly separate disconnected and
  connected lifecycle work.

  ## Examples

  Avoid:

      def mount(params, session, socket) do
        socket = load_data(socket, params, session)
        {:ok, socket}
      end

  Prefer:

      def mount(params, session, socket) do
        if connected?(socket) do
          mount_connected(params, session, socket)
        else
          mount_disconnected(params, session, socket)
        end
      end

      defp mount_connected(params, session, socket) do
        subscribe(params, session)
        {:ok, load_data(socket)}
      end

      defp mount_disconnected(_params, _session, socket) do
        {:ok, assign(socket, :status, :loading)}
      end

  This check forces explicit intent about the LiveView lifecycle phase in which
  work happens. It does not determine whether work is expensive or whether
  either phase is correct. `mount_disconnected/3` may render complete content,
  placeholders, or intentionally repeat work. `mount_connected/3` commonly
  owns connection-only or deliberately deferred work.

  The connected invocation receives its own socket. It does not inherit assigns
  returned by the disconnected invocation. Any assign required in both renders
  must therefore be established in both handlers. Both handlers may call an
  ordinary shared private helper when they intentionally perform the same work.

  ## Options

  This check has no check-specific options. Configure it with an empty option list.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.PhoenixLiveView.RequireExplicitConnectionStateHandlingInMount, []}
        ]
      }
    ]
  }
  ```

  ## Notes

  Phoenix is exploring [adoptable LiveViews](https://github.com/phoenixframework/phoenix_live_view/issues/4317),
  which would preserve the initial LiveView process and eliminate duplicate
  mount work without application changes. If that lifecycle ships, this check
  should be reassessed.

  Intentional exceptions can use definition-level suppression through
  `Bylaw.Credo.Plugin.DisableForNextDefinition`.
  """

  use Credo.Check,
    base_priority: :high,
    category: :design,
    tags: [:web],
    explanations: [
      check: @moduledoc
    ]

  @message "Under LiveView's current lifecycle, mount/3 runs separately for the disconnected render and connected socket. Make mount/3 directly branch on connected?(socket), delegating to mount_connected/3 and mount_disconnected/3, so each operation runs in the intended state."

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    if liveview_file?(source_file.filename) do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.SourceFile.ast()
      |> find_violations(issue_meta)
    else
      []
    end
  end

  defp liveview_file?(filename) do
    not String.ends_with?(filename, "_component.ex") and
      (String.contains?(filename, ["_live/", "live/"]) or
         String.ends_with?(filename, "_live.ex"))
  end

  defp find_violations({:ok, ast}, issue_meta), do: find_violations(ast, issue_meta)

  defp find_violations(ast, issue_meta) when is_tuple(ast) do
    ast
    |> Macro.prewalk([], &traverse(&1, &2, issue_meta))
    |> elem(1)
    |> Enum.sort_by(&{&1.line_no, &1.column})
  end

  defp find_violations(_error, _issue_meta), do: []

  defp traverse({:def, meta, [head, body]} = node, issues, issue_meta) do
    case mount_parameters(head) do
      {:ok, parameters} ->
        parameter_variables = Enum.map(parameters, &forwarding_variable/1)

        if canonical_body?(body, parameter_variables) do
          {node, issues}
        else
          {node, [create_issue(issue_meta, meta) | issues]}
        end

      :error ->
        {node, issues}
    end
  end

  defp traverse(node, issues, _issue_meta), do: {node, issues}

  defp mount_parameters({:mount, _meta, [first, second, third]}),
    do: {:ok, [first, second, third]}

  defp mount_parameters({:when, _meta, [head | _guards]}), do: mount_parameters(head)
  defp mount_parameters(_head), do: :error

  defp forwarding_variable({:=, _meta, [left, right]}) do
    case {variable_identity(left), variable_identity(right)} do
      {nil, {_name, _context} = variable} -> variable
      {{_name, _context} = variable, nil} -> variable
      _other -> nil
    end
  end

  defp forwarding_variable(parameter), do: variable_identity(parameter)

  defp variable_identity({name, _meta, context}) when is_atom(name) and is_atom(context),
    do: {name, context}

  defp variable_identity(_node), do: nil

  defp canonical_body?(
         [do: {:if, _if_meta, [condition, [do: connected_branch, else: disconnected_branch]]}],
         [params, session, socket] = parameter_variables
       ) do
    Enum.all?(parameter_variables) and connected_condition?(condition, socket) and
      local_call?(connected_branch, :mount_connected, [params, session, socket]) and
      local_call?(disconnected_branch, :mount_disconnected, [params, session, socket])
  end

  defp canonical_body?(_body, _parameter_variables), do: false

  defp connected_condition?({:connected?, _meta, [socket]}, expected_socket),
    do: variable_identity(socket) == expected_socket

  defp connected_condition?(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, [:Phoenix, :LiveView]}, :connected?]},
          _call_meta, [socket]},
         expected_socket
       ),
       do: variable_identity(socket) == expected_socket

  defp connected_condition?(_condition, _expected_socket), do: false

  defp local_call?({function, _meta, args}, function, expected_variables)
       when is_list(args) do
    Enum.map(args, &variable_identity/1) == expected_variables
  end

  defp local_call?(_call, _function, _expected_variables), do: false

  defp create_issue(issue_meta, meta) do
    format_issue(
      issue_meta,
      message: @message,
      trigger: "mount",
      line_no: meta[:line] || 0
    )
  end
end
