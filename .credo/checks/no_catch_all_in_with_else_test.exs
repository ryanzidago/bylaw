defmodule Bylaw.Credo.Check.Readability.NoCatchAllInWithElseTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Readability.NoCatchAllInWithElse

  describe "reports catch-all patterns" do
    test "bare variable" do
      """
      defmodule Example do
        def call(id) do
          with {:ok, user} <- fetch_user(id) do
            {:ok, user}
          else
            error -> error
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoCatchAllInWithElse)
      |> assert_issue(%{
        line_no: 6,
        trigger: "error",
        message: ~r/catch-all/
      })
    end

    test "underscore variable" do
      """
      defmodule Example do
        def call(id) do
          with {:ok, user} <- fetch_user(id) do
            {:ok, user}
          else
            _ -> :error
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoCatchAllInWithElse)
      |> assert_issue(%{
        line_no: 6,
        trigger: "_",
        message: ~r/catch-all/
      })
    end

    test "underscore-prefixed variable" do
      """
      defmodule Example do
        def call(id) do
          with {:ok, user} <- fetch_user(id) do
            {:ok, user}
          else
            _error -> :error
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoCatchAllInWithElse)
      |> assert_issue(%{
        line_no: 6,
        trigger: "_error",
        message: ~r/catch-all/
      })
    end

    test "catch-all among explicit clauses" do
      """
      defmodule Example do
        def call(id) do
          with {:ok, user} <- fetch_user(id) do
            {:ok, user}
          else
            {:error, :not_found} -> {:error, :not_found}
            other -> {:error, other}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoCatchAllInWithElse)
      |> assert_issue(%{
        line_no: 7,
        trigger: "other",
        message: ~r/catch-all/
      })
    end
  end

  describe "does not report explicit patterns" do
    test "error tuple pattern" do
      """
      defmodule Example do
        def call(id) do
          with {:ok, user} <- fetch_user(id) do
            {:ok, user}
          else
            {:error, reason} -> {:error, reason}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoCatchAllInWithElse)
      |> refute_issues()
    end

    test "multiple explicit patterns" do
      """
      defmodule Example do
        def call(id) do
          with {:ok, user} <- fetch_user(id),
               {:ok, account} <- fetch_account(user) do
            {:ok, account}
          else
            {:error, :not_found} -> {:error, :not_found}
            {:error, reason} -> {:error, reason}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoCatchAllInWithElse)
      |> refute_issues()
    end

    test "atom pattern" do
      """
      defmodule Example do
        def call(id) do
          with {:ok, user} <- fetch_user(id) do
            {:ok, user}
          else
            :error -> {:error, :unknown}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoCatchAllInWithElse)
      |> refute_issues()
    end

    test "match operator with tuple pattern" do
      """
      defmodule Example do
        def call(id) do
          with {:ok, user} <- fetch_user(id) do
            {:ok, user}
          else
            {:error, _reason} = error -> error
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoCatchAllInWithElse)
      |> refute_issues()
    end

    test "with without else clause is ignored" do
      """
      defmodule Example do
        def call(id) do
          with {:ok, user} <- fetch_user(id) do
            {:ok, user}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoCatchAllInWithElse)
      |> refute_issues()
    end
  end
end
