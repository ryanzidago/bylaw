defmodule Bylaw.HTML.Check do
  @moduledoc """
  Behaviour for checks that validate rendered HTML.

  Each check receives a small validation context containing the original HTML
  string and the parsed document term produced for that HTML.
  """

  alias Bylaw.HTML.Issue

  @typedoc """
  Validation context passed to an HTML check.

  `html` is the original rendered HTML string. `document` is the parsed HTML
  document term produced for that string.
  """
  @type context :: %{html: String.t(), document: term()}

  @typedoc """
  The result returned by an HTML check.
  """
  @type result :: :ok | {:error, nonempty_list(Issue.t())}

  @doc """
  Validates rendered HTML for one check.
  """
  @callback validate(context()) :: result()
end
