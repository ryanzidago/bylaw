defmodule Bylaw.Credo.Check.Ecto.ErrorChangesetPatternMatchTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Ecto.ErrorChangesetPatternMatch

  test "reports bare changeset error patterns" do
    """
    defmodule Example do
      def create(params) do
        case Repo.insert(params) do
          {:ok, record} -> {:ok, record}
          {:error, changeset} -> {:error, changeset}
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(ErrorChangesetPatternMatch)
    |> assert_issue()
  end

  test "does not report explicit changeset struct matches" do
    """
    defmodule Example do
      def create(params) do
        case Repo.insert(params) do
          {:ok, record} -> {:ok, record}
          {:error, %Changeset{} = changeset} -> {:error, changeset}
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(ErrorChangesetPatternMatch)
    |> refute_issues()
  end

  test "does not report non-changeset error names" do
    """
    defmodule Example do
      def create(params) do
        case Repo.insert(params) do
          {:ok, record} -> {:ok, record}
          {:error, reason} -> {:error, reason}
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(ErrorChangesetPatternMatch)
    |> refute_issues()
  end
end
