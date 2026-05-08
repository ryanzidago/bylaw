defmodule Bylaw.Credo.Check.Elixir.NoRaiseTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Elixir.NoRaise

  test "reports raise-like control flow in application code" do
    """
    defmodule Example do
      def run(id) do
        user = Repo.get!(User, id)
        {:ok, account} = Accounts.fetch_account(user)
        Kernel.raise("boom")
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NoRaise)
    |> assert_issues(3)
    |> assert_issues_match([
      %{line_no: 3, trigger: "Repo.get!", message: ~r/Avoid bang functions/},
      %{line_no: 4, trigger: "=", message: ~r/Avoid assertive matches/},
      %{line_no: 5, trigger: "Kernel.raise", message: ~r/Avoid explicit raises/}
    ])
  end

  test "does not report with/else error propagation" do
    """
    defmodule Example do
      def run(id) do
        with {:ok, user} <- Accounts.fetch_user(id),
             {:ok, account} <- Accounts.fetch_account(user) do
          {:ok, account}
        else
          {:error, reason} -> {:error, reason}
        end
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NoRaise)
    |> refute_issues()
  end

  test "does not double report assertive matches around bang calls" do
    """
    defmodule Example do
      def run(changeset) do
        {:ok, user} = Repo.insert!(changeset)
        {:ok, user}
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NoRaise)
    |> assert_issues(1)
    |> assert_issue(%{
      line_no: 3,
      trigger: "Repo.insert!",
      message: ~r/Avoid bang functions/
    })
  end

  test "does not double report assertive matches when a nested or piped call raises" do
    """
    defmodule Example do
      def run(id, changeset) do
        {:ok, user} = Repo.get!(User, id) |> Accounts.wrap_user()
        {:ok, account} = Accounts.wrap_account(Repo.insert!(changeset))
        {user, account}
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NoRaise)
    |> assert_issues(2)
    |> assert_issues_match([
      %{line_no: 3, trigger: "Repo.get!", message: ~r/Avoid bang functions/},
      %{line_no: 4, trigger: "Repo.insert!", message: ~r/Avoid bang functions/}
    ])
  end

  test "does not flag bang function names in definitions" do
    """
    defmodule Example do
      def save!(value), do: value
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NoRaise)
    |> refute_issues()
  end

  test "does not report configured boundary paths" do
    """
    defmodule BylawWeb.Example do
      def variant_name(variants, assigns) do
        Map.fetch!(variants, assigns[:variant])
      end
    end
    """
    |> to_source_file("lib/bylaw_web/example.ex")
    |> run_check(
      NoRaise,
      excluded_paths: [
        ~r{^lib/.+_web/},
        "lib/mix/tasks/",
        "priv/repo/",
        "test/"
      ]
    )
    |> refute_issues()
  end
end
