defmodule Bylaw.HTML do
  @moduledoc """
  Validates rendered HTML strings with explicit checks.

  `validate_html/2` parses the rendered HTML once, runs the checks you choose,
  and returns `:ok` or `{:error, issues}`. Bylaw does not read application
  config or choose default checks for the caller.

  ## Usage

  Choose the checks you want to enforce and pass them with the rendered HTML
  string:

      html = render(view)

      checks = [
        Bylaw.HTML.Check.RequireLinkHref,
        Bylaw.HTML.Check.PreferButtonForAction,
        Bylaw.HTML.Check.PreferLinkForNavigation,
        Bylaw.HTML.Check.RequireImageAlt,
        Bylaw.HTML.Check.RequireButtonType,
        Bylaw.HTML.Check.RequireInputAutocomplete,
        Bylaw.HTML.Check.NoInlineStyle,
        Bylaw.HTML.Check.NoDuplicateAttributes
      ]

      assert :ok = Bylaw.HTML.validate_html(html, checks)

  When validation fails, `validate_html/2` returns every issue found by the
  enabled checks:

      case Bylaw.HTML.validate_html(html, checks) do
        :ok -> :ok
        {:error, issues} -> flunk(inspect(issues, pretty: true))
      end

  ## Built-in checks

  Built-in checks live under `Bylaw.HTML.Check.*`. Each check module documents
  its own examples, notes, options, and copyable check specs.

  ## Notes

  The validation boundary is the rendered HTML string. Checks can see the
  browser-facing markup, but they do not know which source component or template
  produced it.

  ## Examples

      iex> Bylaw.HTML.validate_html(~s(<a href="/settings">Settings</a>), [])
      :ok

      iex> {:error, [issue]} =
      ...>   Bylaw.HTML.validate_html(
      ...>     ~s(<button phx-click='[["navigate",{"href":"/settings","replace":false}]]'>Settings</button>),
      ...>     [Bylaw.HTML.Check.PreferLinkForNavigation]
      ...>   )
      iex> issue.check
      Bylaw.HTML.Check.PreferLinkForNavigation
  """

  alias Bylaw.CheckRunner
  alias Bylaw.HTML.Issue

  @type check :: module()
  @type checks :: list(check())

  @doc """
  Validates rendered `html` with the explicit `checks` list.

  Returns `:ok` when every check passes. Returns `{:error, issues}` when one or
  more issues are found. Validation failures do not raise.

  `checks` must be an explicit list of modules implementing
  `Bylaw.HTML.Check`. Bylaw does not choose default HTML checks or read them
  from application config.
  """
  @spec validate_html(String.t(), checks()) :: :ok | {:error, nonempty_list(Issue.t())}
  def validate_html(html, checks) when is_binary(html) and is_list(checks) do
    checks
    |> normalize_checks!()
    |> validate_parsed_html(html)
  end

  def validate_html(html, _checks) when not is_binary(html) do
    raise ArgumentError, "expected html to be a string, got: #{inspect(html)}"
  end

  def validate_html(_html, checks) do
    raise ArgumentError, "expected checks to be a list, got: #{inspect(checks)}"
  end

  defp validate_parsed_html([], _html), do: :ok

  defp validate_parsed_html(checks, html) do
    case parse_fragment(html) do
      {:ok, document} ->
        context = %{html: html, document: document}

        checks
        |> Enum.flat_map(&issues_for_check(&1, context))
        |> result()

      {:error, _reason} ->
        {:error, [parse_issue(html)]}
    end
  end

  defp parse_fragment(html) do
    {:ok, LazyHTML.from_fragment(html)}
  rescue
    _exception -> {:error, :invalid_html}
  end

  defp normalize_checks!(checks) do
    Enum.map(checks, &ensure_check!/1)
  end

  defp ensure_check!(check) when is_atom(check) do
    with {:module, ^check} <- Code.ensure_loaded(check),
         true <- function_exported?(check, :validate, 1) do
      check
    else
      _not_a_check ->
        raise ArgumentError, "expected #{inspect(check)} to be an HTML check module"
    end
  end

  defp ensure_check!(check) do
    raise ArgumentError, "expected check to be a module, got: #{inspect(check)}"
  end

  defp issues_for_check(check, context) do
    result = check.validate(context)

    apply(CheckRunner, :result!, [check, result, Issue, 1])
  end

  defp parse_issue(html) do
    %Issue{
      check: __MODULE__,
      message: "failed to parse rendered HTML",
      snippet: excerpt(html)
    }
  end

  defp excerpt(html) do
    if String.length(html) > 160 do
      String.slice(html, 0, 160) <> "..."
    else
      html
    end
  end

  defp result([]), do: :ok
  defp result(issues), do: {:error, issues}
end
