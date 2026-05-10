defmodule Bylaw.Credo.Check.Ecto.OwnContextForSchemaTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Ecto.OwnContextForSchema

  test "does not report schemas when schema modules are not configured" do
    """
    defmodule MyApp.Runs.ToolCall do
      use MyApp.Schema

      schema "tool_calls" do
        field :name, :string
      end
    end
    """
    |> to_source_file("lib/my_app/runs/tool_call.ex")
    |> run_check(OwnContextForSchema)
    |> refute_issues()
  end

  test "reports schema under a foreign context" do
    """
    defmodule MyApp.Runs.ToolCall do
      use MyApp.Schema

      schema "tool_calls" do
        field :name, :string
      end
    end
    """
    |> to_source_file("lib/my_app/runs/tool_call.ex")
    |> run_own_context_check()
    |> assert_issue()
    |> assert_issues_match([
      %{
        line_no: 1,
        trigger: "MyApp.Runs.ToolCall",
        message:
          "`ToolCall` should not live under `Runs`. Move it to its own context (e.g. `ToolCalls.ToolCall`)."
      }
    ])
  end

  test "reports schema under a deeply nested foreign context" do
    """
    defmodule MyApp.Billing.Invoices.LineItem do
      use MyApp.Schema

      schema "line_items" do
        field :amount, :integer
      end
    end
    """
    |> to_source_file("lib/my_app/billing/invoices/line_item.ex")
    |> run_own_context_check()
    |> assert_issue()
    |> assert_issues_match([
      %{
        line_no: 1,
        trigger: "MyApp.Billing.Invoices.LineItem",
        message:
          "`LineItem` should not live under `Invoices`. Move it to its own context (e.g. `LineItems.LineItem`)."
      }
    ])
  end

  test "does not report schema under its own context" do
    """
    defmodule MyApp.Runs.Run do
      use MyApp.Schema

      schema "runs" do
        field :status, :string
      end
    end
    """
    |> to_source_file("lib/my_app/runs/run.ex")
    |> run_own_context_check()
    |> refute_issues()
  end

  test "does not report schema whose context starts with schema name" do
    """
    defmodule MyApp.ToolCalls.ToolCall do
      use MyApp.Schema

      schema "tool_calls" do
        field :name, :string
      end
    end
    """
    |> to_source_file("lib/my_app/tool_calls/tool_call.ex")
    |> run_own_context_check()
    |> refute_issues()
  end

  test "does not report schema with pluralized context" do
    """
    defmodule MyApp.Agents.Agent do
      use MyApp.Schema

      schema "agents" do
        field :name, :string
      end
    end
    """
    |> to_source_file("lib/my_app/agents/agent.ex")
    |> run_own_context_check()
    |> refute_issues()
  end

  test "does not report schema with irregular plural context" do
    """
    defmodule MyApp.Addresses.Address do
      use MyApp.Schema

      schema "addresses" do
        field :street, :string
      end
    end
    """
    |> to_source_file("lib/my_app/addresses/address.ex")
    |> run_own_context_check()
    |> refute_issues()
  end

  test "does not report module without use MyApp.Schema" do
    """
    defmodule MyApp.Runs.SomeHelper do
      def help, do: :ok
    end
    """
    |> to_source_file("lib/my_app/runs/some_helper.ex")
    |> run_own_context_check()
    |> refute_issues()
  end

  test "does not report top-level schema module" do
    """
    defmodule MyApp.Schema do
      use MyApp.Schema

      schema "things" do
        field :name, :string
      end
    end
    """
    |> to_source_file("lib/my_app/schema.ex")
    |> run_own_context_check()
    |> refute_issues()
  end

  test "reports AgentTool under Agents context" do
    """
    defmodule MyApp.Agents.AgentTool do
      use MyApp.Schema

      schema "agent_tools" do
        field :agent_id, :string
        field :tool_id, :string
      end
    end
    """
    |> to_source_file("lib/my_app/agents/agent_tool.ex")
    |> run_own_context_check()
    |> assert_issue()
    |> assert_issues_match([
      %{
        line_no: 1,
        trigger: "MyApp.Agents.AgentTool",
        message:
          "`AgentTool` should not live under `Agents`. Move it to its own context (e.g. `AgentTools.AgentTool`)."
      }
    ])
  end

  test "does not report AgentTool under AgentTools context" do
    """
    defmodule MyApp.AgentTools.AgentTool do
      use MyApp.Schema

      schema "agent_tools" do
        field :agent_id, :string
        field :tool_id, :string
      end
    end
    """
    |> to_source_file("lib/my_app/agent_tools/agent_tool.ex")
    |> run_own_context_check()
    |> refute_issues()
  end

  test "handles Account under Accounts" do
    """
    defmodule MyApp.Accounts.Account do
      use MyApp.Schema

      schema "accounts" do
        field :name, :string
      end
    end
    """
    |> to_source_file("lib/my_app/accounts/account.ex")
    |> run_own_context_check()
    |> refute_issues()
  end

  test "reports TenantUser under Accounts" do
    """
    defmodule MyApp.Accounts.TenantUser do
      use MyApp.Schema

      schema "tenant_users" do
        field :tenant_id, :string
      end
    end
    """
    |> to_source_file("lib/my_app/accounts/tenant_user.ex")
    |> run_own_context_check()
    |> assert_issue()
  end

  test "does not report excluded modules" do
    """
    defmodule MyApp.Runs.ToolCall do
      use MyApp.Schema

      schema "tool_calls" do
        field :name, :string
      end
    end
    """
    |> to_source_file("lib/my_app/runs/tool_call.ex")
    |> run_own_context_check(excluded_modules: ["MyApp.Runs.ToolCall"])
    |> refute_issues()
  end

  test "still reports non-excluded modules when exclusions are configured" do
    """
    defmodule MyApp.Runs.SomethingElse do
      use MyApp.Schema

      schema "something_elses" do
        field :name, :string
      end
    end
    """
    |> to_source_file("lib/my_app/runs/something_else.ex")
    |> run_own_context_check(excluded_modules: ["MyApp.Runs.ToolCall"])
    |> assert_issue()
  end

  defp run_own_context_check(source_file, opts \\ []) do
    run_check(
      source_file,
      OwnContextForSchema,
      Keyword.put_new(opts, :schema_modules, [MyApp.Schema])
    )
  end
end
