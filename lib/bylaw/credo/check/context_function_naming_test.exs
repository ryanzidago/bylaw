defmodule Bylaw.Credo.Check.ContextFunctionNamingTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.ContextFunctionNaming

  describe "get_* with tagged tuple return" do
    test "reports get_ function returning {:ok, ...} | {:error, ...}" do
      """
      defmodule MyApp.Workspaces do
        @spec get_workspace(binary(), binary()) :: {:ok, Workspace.t()} | {:error, :not_found}
        def get_workspace(tenant_id, id) do
          case Repo.get_by(Workspace, id: id, tenant_id: tenant_id) do
            %Workspace{} = ws -> {:ok, ws}
            nil -> {:error, :not_found}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(ContextFunctionNaming)
      |> assert_issues(1)
      |> assert_issues_match([
        %{line_no: 2, trigger: "get_workspace", message: ~r/fetch_workspace/}
      ])
    end

    test "reports get_ function returning {:ok, ...} | {:error, ...} with multiple error variants" do
      """
      defmodule MyApp.Accounts do
        @spec get_user(binary()) :: {:ok, User.t()} | {:error, :not_found} | {:error, :disabled}
        def get_user(id), do: :stub
      end
      """
      |> to_source_file()
      |> run_check(ContextFunctionNaming)
      |> assert_issues(1)
    end
  end

  describe "get_* with correct return" do
    test "does not report get_ function returning record | nil" do
      """
      defmodule MyApp.Workspaces do
        @spec get_workspace(binary(), binary()) :: Workspace.t() | nil
        def get_workspace(tenant_id, id) do
          Repo.get_by(Workspace, id: id, tenant_id: tenant_id)
        end
      end
      """
      |> to_source_file()
      |> run_check(ContextFunctionNaming)
      |> refute_issues()
    end

    test "does not report get_ function returning just a struct" do
      """
      defmodule MyApp.Config do
        @spec get_setting(binary()) :: Setting.t()
        def get_setting(key), do: :stub
      end
      """
      |> to_source_file()
      |> run_check(ContextFunctionNaming)
      |> refute_issues()
    end
  end

  describe "fetch_* with correct return" do
    test "does not report fetch_ function returning {:ok, ...} | {:error, ...}" do
      """
      defmodule MyApp.Workspaces do
        @spec fetch_workspace(binary(), binary()) :: {:ok, Workspace.t()} | {:error, :not_found}
        def fetch_workspace(tenant_id, id) do
          case Repo.get_by(Workspace, id: id, tenant_id: tenant_id) do
            %Workspace{} = ws -> {:ok, ws}
            nil -> {:error, :not_found}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(ContextFunctionNaming)
      |> refute_issues()
    end

    test "reports fetch_ function returning only {:ok, ...}" do
      """
      defmodule MyApp.Workspaces do
        @spec fetch_workspace(binary()) :: {:ok, Workspace.t()}
        def fetch_workspace(id), do: :stub
      end
      """
      |> to_source_file()
      |> run_check(ContextFunctionNaming)
      |> assert_issues(1)
      |> assert_issues_match([
        %{line_no: 2, trigger: "fetch_workspace", message: ~r/does not return/}
      ])
    end

    test "reports fetch_ function returning only {:error, ...}" do
      """
      defmodule MyApp.Workspaces do
        @spec fetch_workspace(binary()) :: {:error, :not_found}
        def fetch_workspace(id), do: :stub
      end
      """
      |> to_source_file()
      |> run_check(ContextFunctionNaming)
      |> assert_issues(1)
      |> assert_issues_match([
        %{line_no: 2, trigger: "fetch_workspace", message: ~r/does not return/}
      ])
    end
  end

  describe "fetch_* with incorrect return" do
    test "reports fetch_ function returning record | nil" do
      """
      defmodule MyApp.Workspaces do
        @spec fetch_workspace(binary(), binary()) :: Workspace.t() | nil
        def fetch_workspace(tenant_id, id) do
          Repo.get_by(Workspace, id: id, tenant_id: tenant_id)
        end
      end
      """
      |> to_source_file()
      |> run_check(ContextFunctionNaming)
      |> assert_issues(1)
      |> assert_issues_match([
        %{line_no: 2, trigger: "fetch_workspace", message: ~r/does not return/}
      ])
    end

    test "reports fetch_ function returning just a struct" do
      """
      defmodule MyApp.Config do
        @spec fetch_setting(binary()) :: Setting.t()
        def fetch_setting(key), do: :stub
      end
      """
      |> to_source_file()
      |> run_check(ContextFunctionNaming)
      |> assert_issues(1)
    end
  end

  describe "get_*! (bang) functions" do
    test "does not report get_! function returning just a record" do
      """
      defmodule MyApp.Workspaces do
        @spec get_workspace!(binary(), binary()) :: Workspace.t()
        def get_workspace!(tenant_id, id) do
          Repo.get_by!(Workspace, id: id, tenant_id: tenant_id)
        end
      end
      """
      |> to_source_file()
      |> run_check(ContextFunctionNaming)
      |> refute_issues()
    end

    test "reports get_! function returning tagged tuples" do
      """
      defmodule MyApp.Workspaces do
        @spec get_workspace!(binary(), binary()) :: {:ok, Workspace.t()} | {:error, :not_found}
        def get_workspace!(tenant_id, id), do: :stub
      end
      """
      |> to_source_file()
      |> run_check(ContextFunctionNaming)
      |> assert_issues(1)
      |> assert_issues_match([
        %{line_no: 2, trigger: "get_workspace!", message: ~r/bang/}
      ])
    end

    test "reports get_! function returning record | nil" do
      """
      defmodule MyApp.Workspaces do
        @spec get_workspace!(binary()) :: Workspace.t() | nil
        def get_workspace!(id), do: :stub
      end
      """
      |> to_source_file()
      |> run_check(ContextFunctionNaming)
      |> assert_issues(1)
      |> assert_issues_match([
        %{line_no: 2, trigger: "get_workspace!", message: ~r/record directly or raise/}
      ])
    end
  end

  describe "unrelated functions" do
    test "does not report functions without get_ or fetch_ prefix" do
      """
      defmodule MyApp.Workspaces do
        @spec list_workspaces(binary()) :: {:ok, {list(Workspace.t()), Flop.Meta.t()}}
        def list_workspaces(tenant_id), do: :stub

        @spec create_workspace(binary(), map()) :: {:ok, Workspace.t()} | {:error, Ecto.Changeset.t()}
        def create_workspace(tenant_id, attrs), do: :stub

        @spec delete_workspace(binary(), binary()) :: {:ok, Workspace.t()} | {:error, :not_found}
        def delete_workspace(tenant_id, id), do: :stub
      end
      """
      |> to_source_file()
      |> run_check(ContextFunctionNaming)
      |> refute_issues()
    end
  end

  describe "specs with when clauses" do
    test "reports get_ with tagged tuples in spec with when clause" do
      """
      defmodule MyApp.Workspaces do
        @spec get_workspace(id) :: {:ok, Workspace.t()} | {:error, :not_found} when id: binary()
        def get_workspace(id), do: :stub
      end
      """
      |> to_source_file()
      |> run_check(ContextFunctionNaming)
      |> assert_issues(1)
    end
  end

  describe "excluded_paths" do
    test "does not report issues for excluded paths" do
      """
      defmodule MyApp.Workspaces do
        @spec get_workspace(binary()) :: {:ok, Workspace.t()} | {:error, :not_found}
        def get_workspace(id), do: :stub
      end
      """
      |> to_source_file("lib/my_app/workspaces.ex")
      |> run_check(ContextFunctionNaming, excluded_paths: ["lib/my_app/"])
      |> refute_issues()
    end

    test "does not report issues for excluded regex paths" do
      """
      defmodule MyApp.Workspaces do
        @spec get_workspace(binary()) :: {:ok, Workspace.t()} | {:error, :not_found}
        def get_workspace(id), do: :stub
      end
      """
      |> to_source_file("lib/my_app/workspaces.ex")
      |> run_check(ContextFunctionNaming, excluded_paths: [~r/lib\/my_app\//])
      |> refute_issues()
    end
  end
end
