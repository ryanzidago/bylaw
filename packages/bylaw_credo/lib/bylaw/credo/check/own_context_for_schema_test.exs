defmodule Bylaw.Credo.Check.OwnContextForSchemaTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.OwnContextForSchema

  test "reports schema under a foreign context" do
    """
    defmodule Bylaw.Runs.ToolCall do
      use Bylaw.Schema

      schema "tool_calls" do
        field :name, :string
      end
    end
    """
    |> to_source_file("lib/bylaw/runs/tool_call.ex")
    |> run_check(OwnContextForSchema)
    |> assert_issue()
    |> assert_issues_match([
      %{
        line_no: 1,
        trigger: "Bylaw.Runs.ToolCall",
        message:
          "`ToolCall` should not live under `Runs`. Move it to its own context (e.g. `ToolCalls.ToolCall`)."
      }
    ])
  end

  test "reports schema under a deeply nested foreign context" do
    """
    defmodule Bylaw.Billing.Invoices.LineItem do
      use Bylaw.Schema

      schema "line_items" do
        field :amount, :integer
      end
    end
    """
    |> to_source_file("lib/bylaw/billing/invoices/line_item.ex")
    |> run_check(OwnContextForSchema)
    |> assert_issue()
    |> assert_issues_match([
      %{
        line_no: 1,
        trigger: "Bylaw.Billing.Invoices.LineItem",
        message:
          "`LineItem` should not live under `Invoices`. Move it to its own context (e.g. `LineItems.LineItem`)."
      }
    ])
  end

  test "does not report schema under its own context" do
    """
    defmodule Bylaw.Runs.Run do
      use Bylaw.Schema

      schema "runs" do
        field :status, :string
      end
    end
    """
    |> to_source_file("lib/bylaw/runs/run.ex")
    |> run_check(OwnContextForSchema)
    |> refute_issues()
  end

  test "does not report schema whose context starts with schema name" do
    """
    defmodule Bylaw.ToolCalls.ToolCall do
      use Bylaw.Schema

      schema "tool_calls" do
        field :name, :string
      end
    end
    """
    |> to_source_file("lib/bylaw/tool_calls/tool_call.ex")
    |> run_check(OwnContextForSchema)
    |> refute_issues()
  end

  test "does not report schema with pluralized context" do
    """
    defmodule Bylaw.Agents.Agent do
      use Bylaw.Schema

      schema "agents" do
        field :name, :string
      end
    end
    """
    |> to_source_file("lib/bylaw/agents/agent.ex")
    |> run_check(OwnContextForSchema)
    |> refute_issues()
  end

  test "does not report schema with irregular plural context" do
    """
    defmodule Bylaw.Addresses.Address do
      use Bylaw.Schema

      schema "addresses" do
        field :street, :string
      end
    end
    """
    |> to_source_file("lib/bylaw/addresses/address.ex")
    |> run_check(OwnContextForSchema)
    |> refute_issues()
  end

  test "does not report module without use Bylaw.Schema" do
    """
    defmodule Bylaw.Runs.SomeHelper do
      def help, do: :ok
    end
    """
    |> to_source_file("lib/bylaw/runs/some_helper.ex")
    |> run_check(OwnContextForSchema)
    |> refute_issues()
  end

  test "does not report top-level schema module" do
    """
    defmodule Bylaw.Schema do
      use Bylaw.Schema

      schema "things" do
        field :name, :string
      end
    end
    """
    |> to_source_file("lib/bylaw/schema.ex")
    |> run_check(OwnContextForSchema)
    |> refute_issues()
  end

  test "reports AgentTool under Agents context" do
    """
    defmodule Bylaw.Agents.AgentTool do
      use Bylaw.Schema

      schema "agent_tools" do
        field :agent_id, :string
        field :tool_id, :string
      end
    end
    """
    |> to_source_file("lib/bylaw/agents/agent_tool.ex")
    |> run_check(OwnContextForSchema)
    |> assert_issue()
    |> assert_issues_match([
      %{
        line_no: 1,
        trigger: "Bylaw.Agents.AgentTool",
        message:
          "`AgentTool` should not live under `Agents`. Move it to its own context (e.g. `AgentTools.AgentTool`)."
      }
    ])
  end

  test "does not report AgentTool under AgentTools context" do
    """
    defmodule Bylaw.AgentTools.AgentTool do
      use Bylaw.Schema

      schema "agent_tools" do
        field :agent_id, :string
        field :tool_id, :string
      end
    end
    """
    |> to_source_file("lib/bylaw/agent_tools/agent_tool.ex")
    |> run_check(OwnContextForSchema)
    |> refute_issues()
  end

  test "handles Account under Accounts" do
    """
    defmodule Bylaw.Accounts.Account do
      use Bylaw.Schema

      schema "accounts" do
        field :name, :string
      end
    end
    """
    |> to_source_file("lib/bylaw/accounts/account.ex")
    |> run_check(OwnContextForSchema)
    |> refute_issues()
  end

  test "reports TenantUser under Accounts" do
    """
    defmodule Bylaw.Accounts.TenantUser do
      use Bylaw.Schema

      schema "tenant_users" do
        field :tenant_id, :string
      end
    end
    """
    |> to_source_file("lib/bylaw/accounts/tenant_user.ex")
    |> run_check(OwnContextForSchema)
    |> assert_issue()
  end

  test "does not report excluded modules" do
    """
    defmodule Bylaw.Runs.ToolCall do
      use Bylaw.Schema

      schema "tool_calls" do
        field :name, :string
      end
    end
    """
    |> to_source_file("lib/bylaw/runs/tool_call.ex")
    |> run_check(OwnContextForSchema, excluded_modules: ["Bylaw.Runs.ToolCall"])
    |> refute_issues()
  end

  test "still reports non-excluded modules when exclusions are configured" do
    """
    defmodule Bylaw.Runs.SomethingElse do
      use Bylaw.Schema

      schema "something_elses" do
        field :name, :string
      end
    end
    """
    |> to_source_file("lib/bylaw/runs/something_else.ex")
    |> run_check(OwnContextForSchema, excluded_modules: ["Bylaw.Runs.ToolCall"])
    |> assert_issue()
  end
end
