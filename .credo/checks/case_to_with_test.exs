defmodule Bylaw.Credo.Check.Refactor.CaseToWithTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Refactor.CaseToWith

  describe "reports case expressions that should be with" do
    test "basic case with ok/error where error is passed through" do
      """
      defmodule Example do
        def call(id) do
          case fetch_user(id) do
            {:ok, user} -> update_user(user)
            {:error, error} -> {:error, error}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(CaseToWith)
      |> assert_issue(%{
        line_no: 3,
        trigger: "case",
        message: ~r/Refactor.*with/
      })
    end

    test "error clause uses = match and returns bound variable" do
      """
      defmodule Example do
        def call(id) do
          case fetch_user(id) do
            {:ok, user} -> update_user(user)
            {:error, _reason} = error -> error
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(CaseToWith)
      |> assert_issue(%{
        line_no: 3,
        trigger: "case"
      })
    end

    test "error clause supports reversed = match and returns bound variable" do
      """
      defmodule Example do
        def call(id) do
          case fetch_user(id) do
            {:ok, user} -> update_user(user)
            error = {:error, _reason} -> error
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(CaseToWith)
      |> assert_issue(%{
        line_no: 3,
        trigger: "case"
      })
    end

    test "error clause with bare :error atom pass-through" do
      """
      defmodule Example do
        def call(id) do
          case fetch_user(id) do
            {:ok, user} -> do_something(user)
            :error -> :error
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(CaseToWith)
      |> assert_issue(%{
        line_no: 3,
        trigger: "case"
      })
    end

    test "ok branch has a multi-line block ending with a function call" do
      """
      defmodule Example do
        def call(id) do
          case fetch_user(id) do
            {:ok, user} ->
              Logger.info("found user")
              update_user(user)

            {:error, error} ->
              {:error, error}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(CaseToWith)
      |> assert_issue(%{
        line_no: 3,
        trigger: "case"
      })
    end

    test "ok clause supports = match with tuple on the left" do
      """
      defmodule Example do
        def call(id) do
          case fetch_user(id) do
            {:ok, user} = result -> persist_user(result, user)
            {:error, error} -> {:error, error}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(CaseToWith)
      |> assert_issue(%{
        line_no: 3,
        trigger: "case"
      })
    end

    test "ok clause supports = match with tuple on the right" do
      """
      defmodule Example do
        def call(id) do
          case fetch_user(id) do
            result = {:ok, user} -> persist_user(result, user)
            {:error, error} -> {:error, error}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(CaseToWith)
      |> assert_issue(%{
        line_no: 3,
        trigger: "case"
      })
    end

    test "ok branch pipes into another function" do
      """
      defmodule Example do
        def call(id) do
          case fetch_user(id) do
            {:ok, user} -> user |> update_user()
            {:error, error} -> {:error, error}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(CaseToWith)
      |> assert_issue(%{
        line_no: 3,
        trigger: "case"
      })
    end

    test "ok branch ends in a remote function call" do
      """
      defmodule Example do
        def call(id) do
          case fetch_user(id) do
            {:ok, user} -> Accounts.update_user(user)
            {:error, error} -> {:error, error}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(CaseToWith)
      |> assert_issue(%{
        line_no: 3,
        trigger: "case"
      })
    end

    test "nested case inside ok branch (chain of ok/error)" do
      """
      defmodule Example do
        def call(id) do
          case fetch_user(id) do
            {:ok, user} ->
              case fetch_account(user) do
                {:ok, account} -> update_account(account)
                {:error, error} -> {:error, error}
              end

            {:error, error} ->
              {:error, error}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(CaseToWith)
      |> assert_issues(2)
    end

    test "error clause returns error with different variable name" do
      """
      defmodule Example do
        def call(id) do
          case fetch_user(id) do
            {:ok, user} -> process(user)
            {:error, reason} -> {:error, reason}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(CaseToWith)
      |> assert_issue(%{
        line_no: 3,
        trigger: "case"
      })
    end

    test "error clause with underscore-prefixed variable pass-through" do
      """
      defmodule Example do
        def call(id) do
          case fetch_user(id) do
            {:ok, user} -> process(user)
            {:error, _reason} = error -> error
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(CaseToWith)
      |> assert_issue(%{
        line_no: 3,
        trigger: "case"
      })
    end

    test "case subject is a remote function call" do
      """
      defmodule Example do
        def call(id) do
          case Accounts.fetch_user(id) do
            {:ok, user} -> update_user(user)
            {:error, error} -> {:error, error}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(CaseToWith)
      |> assert_issue(%{
        line_no: 3,
        trigger: "case"
      })
    end

    test "case subject is a pipe chain" do
      """
      defmodule Example do
        def call(id) do
          case id |> fetch_user() do
            {:ok, user} -> update_user(user)
            {:error, error} -> {:error, error}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(CaseToWith)
      |> assert_issue(%{
        line_no: 3,
        trigger: "case"
      })
    end

    test "multiple error clauses that all pass through" do
      """
      defmodule Example do
        def call(id) do
          case fetch_user(id) do
            {:ok, user} -> process(user)
            {:error, :not_found} -> {:error, :not_found}
            {:error, :forbidden} -> {:error, :forbidden}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(CaseToWith)
      |> assert_issue(%{
        line_no: 3,
        trigger: "case"
      })
    end
  end

  describe "does not report case expressions that should stay as case" do
    test "case where error clause does real work (not pass-through)" do
      """
      defmodule Example do
        def call(id) do
          case fetch_user(id) do
            {:ok, user} -> update_user(user)
            {:error, error} -> Logger.error(error)
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(CaseToWith)
      |> refute_issues()
    end

    test "case where error clause wraps the error differently" do
      """
      defmodule Example do
        def call(id) do
          case fetch_user(id) do
            {:ok, user} -> update_user(user)
            {:error, reason} -> {:error, {:user_fetch_failed, reason}}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(CaseToWith)
      |> refute_issues()
    end

    test "case matching on non-ok/error patterns" do
      """
      defmodule Example do
        def call(value) do
          case value do
            :foo -> handle_foo()
            :bar -> handle_bar()
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(CaseToWith)
      |> refute_issues()
    end

    test "case with more than ok/error branches" do
      """
      defmodule Example do
        def call(id) do
          case fetch_user(id) do
            {:ok, user} -> process(user)
            {:error, error} -> {:error, error}
            :pending -> :retry
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(CaseToWith)
      |> refute_issues()
    end

    test "case where ok branch returns a plain value" do
      """
      defmodule Example do
        def call(id) do
          case fetch_user(id) do
            {:ok, user} -> user.name
            {:error, error} -> {:error, error}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(CaseToWith)
      |> refute_issues()
    end

    test "case where ok branch returns a literal" do
      """
      defmodule Example do
        def call(id) do
          case fetch_user(id) do
            {:ok, _user} -> :ok
            {:error, error} -> {:error, error}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(CaseToWith)
      |> refute_issues()
    end

    test "case where ok branch returns a tuple" do
      """
      defmodule Example do
        def call(id) do
          case fetch_user(id) do
            {:ok, user} -> {:ok, user.name}
            {:error, error} -> {:error, error}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(CaseToWith)
      |> refute_issues()
    end

    test "case where ok branch returns a map" do
      """
      defmodule Example do
        def call(id) do
          case fetch_user(id) do
            {:ok, user} -> %{name: user.name}
            {:error, error} -> {:error, error}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(CaseToWith)
      |> refute_issues()
    end

    test "case where ok branch returns a list" do
      """
      defmodule Example do
        def call(id) do
          case fetch_user(id) do
            {:ok, user} -> [user | users]
            {:error, error} -> {:error, error}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(CaseToWith)
      |> refute_issues()
    end

    test "case with catch-all pattern" do
      """
      defmodule Example do
        def call(id) do
          case fetch_user(id) do
            {:ok, user} -> process(user)
            _ -> :error
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(CaseToWith)
      |> refute_issues()
    end

    test "case where error clause returns a different tag" do
      """
      defmodule Example do
        def call(id) do
          case fetch_user(id) do
            {:ok, user} -> process(user)
            {:error, reason} -> {:failure, reason}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(CaseToWith)
      |> refute_issues()
    end

    test "case where subject is a variable, not a function call" do
      """
      defmodule Example do
        def call(result) do
          case result do
            {:ok, user} -> process(user)
            {:error, error} -> {:error, error}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(CaseToWith)
      |> refute_issues()
    end

    test "case with no error clause" do
      """
      defmodule Example do
        def call(id) do
          case fetch_user(id) do
            {:ok, user} -> process(user)
            nil -> :not_found
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(CaseToWith)
      |> refute_issues()
    end

    test "plain case with string patterns" do
      """
      defmodule Example do
        def call(input) do
          case String.trim(input) do
            "" -> :empty
            value -> value
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(CaseToWith)
      |> refute_issues()
    end

    test "case where error clause logs and returns" do
      """
      defmodule Example do
        def call(id) do
          case fetch_user(id) do
            {:ok, user} -> process(user)
            {:error, error} ->
              Logger.error("Failed: \#{inspect(error)}")
              {:error, error}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(CaseToWith)
      |> refute_issues()
    end
  end
end
