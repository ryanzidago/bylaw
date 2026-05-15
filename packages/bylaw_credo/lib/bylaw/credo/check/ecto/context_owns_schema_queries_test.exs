defmodule Bylaw.Credo.Check.Ecto.ContextOwnsSchemaQueriesTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Ecto.ContextOwnsSchemaQueries

  test "owner context may query its schema" do
    """
    defmodule MyApp.Conversations do
      import Ecto.Query
      alias MyApp.Conversations.Conversation

      def fetch(id) do
        from(c in Conversation, where: c.id == ^id)
      end
    end
    """
    |> to_source_file("lib/my_app/conversations.ex")
    |> run_context_check()
    |> refute_issues()
  end

  test "nested module under owner namespace may not query the schema" do
    """
    defmodule MyApp.Conversations.Detail do
      import Ecto.Query
      alias MyApp.Conversations.Conversation

      def query do
        from(c in Conversation, where: c.visible)
      end
    end
    """
    |> to_source_file("lib/my_app/conversations/detail.ex")
    |> run_context_check()
    |> assert_issue(%{
      line_no: 6,
      trigger: "from",
      message:
        "Only MyApp.Conversations may write Ecto queries for MyApp.Conversations.Conversation. Call the owning context or add a function there."
    })
  end

  test "another context may not query the schema" do
    """
    defmodule MyApp.Branches do
      import Ecto.Query
      alias MyApp.Conversations.Conversation

      def query do
        from(c in Conversation, where: c.visible)
      end
    end
    """
    |> to_source_file("lib/my_app/branches.ex")
    |> run_context_check()
    |> assert_issue(%{line_no: 6, trigger: "from"})
  end

  test "another context may call the owner context function" do
    """
    defmodule MyApp.Branches do
      alias MyApp.Conversations

      def fetch(id) do
        Conversations.fetch_conversation(id)
      end
    end
    """
    |> to_source_file("lib/my_app/branches.ex")
    |> run_context_check()
    |> refute_issues()
  end

  test "pattern matching on schema structs outside the owner is allowed" do
    """
    defmodule MyApp.Branches do
      alias MyApp.Conversations.Conversation

      def handle(%Conversation{} = conversation) do
        conversation.id
      end
    end
    """
    |> to_source_file("lib/my_app/branches.ex")
    |> run_context_check()
    |> refute_issues()
  end

  test "typespec references are allowed" do
    """
    defmodule MyApp.Branches do
      alias MyApp.Conversations.Conversation

      @spec render(Conversation.t()) :: map()
      def render(conversation), do: %{id: conversation.id}
    end
    """
    |> to_source_file("lib/my_app/branches.ex")
    |> run_context_check()
    |> refute_issues()
  end

  test "aliases alone are allowed" do
    """
    defmodule MyApp.Branches do
      alias MyApp.Conversations.Conversation
      alias MyApp.Conversations.{Message, Thread}
    end
    """
    |> to_source_file("lib/my_app/branches.ex")
    |> run_context_check()
    |> refute_issues()
  end

  test "from c in schema is flagged" do
    """
    defmodule MyApp.Branches do
      import Ecto.Query
      alias MyApp.Conversations.Conversation

      def query do
        from(c in Conversation, where: c.id == 1)
      end
    end
    """
    |> to_source_file("lib/my_app/branches.ex")
    |> run_context_check()
    |> assert_issue(%{line_no: 6, trigger: "from"})
  end

  test "from schema with keyword clauses is flagged" do
    """
    defmodule MyApp.Branches do
      import Ecto.Query
      alias MyApp.Conversations.Conversation

      def query do
        from(Conversation, where: [published: true])
      end
    end
    """
    |> to_source_file("lib/my_app/branches.ex")
    |> run_context_check()
    |> assert_issue(%{line_no: 6, trigger: "from"})
  end

  test "schema piped into where is flagged" do
    """
    defmodule MyApp.Branches do
      import Ecto.Query
      alias MyApp.Conversations.Conversation

      def query do
        Conversation
        |> where([c], c.id == 1)
      end
    end
    """
    |> to_source_file("lib/my_app/branches.ex")
    |> run_context_check()
    |> assert_issue(%{line_no: 7, trigger: "where"})
  end

  test "schema piped into remote Ecto query function is flagged" do
    """
    defmodule MyApp.Branches do
      alias MyApp.Conversations.Conversation

      def query do
        Conversation
        |> Ecto.Query.where([c], c.id == 1)
      end
    end
    """
    |> to_source_file("lib/my_app/branches.ex")
    |> run_context_check()
    |> assert_issue(%{line_no: 6, trigger: "Ecto.Query.where"})
  end

  test "remote Ecto query function against schema is flagged" do
    """
    defmodule MyApp.Branches do
      alias MyApp.Conversations.Conversation

      def query do
        Ecto.Query.where(Conversation, [c], c.id == 1)
      end
    end
    """
    |> to_source_file("lib/my_app/branches.ex")
    |> run_context_check()
    |> assert_issue(%{line_no: 5, trigger: "Ecto.Query.where"})
  end

  test "repo get_by against schema is flagged" do
    """
    defmodule MyApp.Branches do
      alias MyApp.Conversations.Conversation
      alias MyApp.Repo

      def fetch(slug) do
        Repo.get_by(Conversation, slug: slug)
      end
    end
    """
    |> to_source_file("lib/my_app/branches.ex")
    |> run_context_check()
    |> assert_issue(%{line_no: 6, trigger: "Repo.get_by"})
  end

  test "repo all against schema is flagged" do
    """
    defmodule MyApp.Branches do
      alias MyApp.Conversations.Conversation
      alias MyApp.Repo

      def all do
        Repo.all(Conversation)
      end
    end
    """
    |> to_source_file("lib/my_app/branches.ex")
    |> run_context_check()
    |> assert_issue(%{line_no: 6, trigger: "Repo.all"})
  end

  test "schema piped into repo all is flagged" do
    """
    defmodule MyApp.Branches do
      alias MyApp.Conversations.Conversation
      alias MyApp.Repo

      def all do
        Conversation
        |> Repo.all()
      end
    end
    """
    |> to_source_file("lib/my_app/branches.ex")
    |> run_context_check()
    |> assert_issue(%{line_no: 7, trigger: "Repo.all"})
  end

  test "repo aggregate against schema is flagged" do
    """
    defmodule MyApp.Branches do
      alias MyApp.Conversations.Conversation
      alias MyApp.Repo

      def count do
        Repo.aggregate(Conversation, :count)
      end
    end
    """
    |> to_source_file("lib/my_app/branches.ex")
    |> run_context_check()
    |> assert_issue(%{line_no: 6, trigger: "Repo.aggregate"})
  end

  test "repo insert of schema struct is flagged" do
    """
    defmodule MyApp.Branches do
      alias MyApp.Conversations.Conversation
      alias MyApp.Repo

      def create(attrs) do
        Repo.insert(%Conversation{name: attrs.name})
      end
    end
    """
    |> to_source_file("lib/my_app/branches.ex")
    |> run_context_check()
    |> assert_issue(%{line_no: 6, trigger: "Repo.insert"})
  end

  test "schema struct piped into repo insert is flagged" do
    """
    defmodule MyApp.Branches do
      alias MyApp.Conversations.Conversation
      alias MyApp.Repo

      def create(attrs) do
        %Conversation{name: attrs.name}
        |> Repo.insert()
      end
    end
    """
    |> to_source_file("lib/my_app/branches.ex")
    |> run_context_check()
    |> assert_issue(%{line_no: 7, trigger: "Repo.insert"})
  end

  test "repo update of schema changeset is flagged when detectable" do
    """
    defmodule MyApp.Branches do
      alias MyApp.Conversations.Conversation
      alias MyApp.Repo

      def update(conversation, attrs) do
        Repo.update(Conversation.changeset(conversation, attrs))
      end
    end
    """
    |> to_source_file("lib/my_app/branches.ex")
    |> run_context_check()
    |> assert_issue(%{line_no: 6, trigger: "Repo.update"})
  end

  test "repo delete bang of schema struct is flagged" do
    """
    defmodule MyApp.Branches do
      alias MyApp.Conversations.Conversation
      alias MyApp.Repo

      def delete do
        Repo.delete!(%Conversation{})
      end
    end
    """
    |> to_source_file("lib/my_app/branches.ex")
    |> run_context_check()
    |> assert_issue(%{line_no: 6, trigger: "Repo.delete!"})
  end

  test "fully qualified schema modules are detected" do
    """
    defmodule MyApp.Branches do
      import Ecto.Query

      def query do
        from(c in MyApp.Conversations.Conversation, where: c.id == 1)
      end
    end
    """
    |> to_source_file("lib/my_app/branches.ex")
    |> run_context_check()
    |> assert_issue(%{line_no: 5, trigger: "from"})
  end

  test "multi-alias syntax is detected" do
    """
    defmodule MyApp.Branches do
      import Ecto.Query
      alias MyApp.Conversations.{Conversation, Message}

      def query do
        from(m in Message, where: m.id == 1)
      end
    end
    """
    |> to_source_file("lib/my_app/branches.ex")
    |> run_context_check()
    |> assert_issue(%{
      line_no: 6,
      trigger: "from",
      message: ~r/MyApp\.Conversations\.Message/
    })
  end

  test "alias as syntax is detected" do
    """
    defmodule MyApp.Branches do
      import Ecto.Query
      alias MyApp.Conversations.Conversation, as: Chat

      def query do
        from(c in Chat, where: c.id == 1)
      end
    end
    """
    |> to_source_file("lib/my_app/branches.ex")
    |> run_context_check()
    |> assert_issue(%{
      line_no: 6,
      trigger: "from",
      message: ~r/MyApp\.Conversations\.Conversation/
    })
  end

  test "excluded modules are respected" do
    """
    defmodule MyApp.Branches.Legacy do
      import Ecto.Query
      alias MyApp.Conversations.Conversation

      def query do
        from(c in Conversation, where: c.id == 1)
      end
    end
    """
    |> to_source_file("lib/my_app/branches/legacy.ex")
    |> run_context_check(excluded_modules: [MyApp.Branches.Legacy])
    |> refute_issues()
  end

  test "excluded modules can be configured as strings" do
    """
    defmodule MyApp.Branches.Legacy do
      import Ecto.Query
      alias MyApp.Conversations.Conversation

      def query do
        from(c in Conversation, where: c.id == 1)
      end
    end
    """
    |> to_source_file("lib/my_app/branches/legacy.ex")
    |> run_context_check(excluded_modules: ["MyApp.Branches.Legacy"])
    |> refute_issues()
  end

  test "excluded paths are respected" do
    """
    defmodule MyApp.Branches.Generated do
      import Ecto.Query
      alias MyApp.Conversations.Conversation

      def query do
        from(c in Conversation, where: c.id == 1)
      end
    end
    """
    |> to_source_file("lib/my_app/generated/branches.ex")
    |> run_context_check(excluded_paths: ["lib/my_app/generated/"])
    |> refute_issues()
  end

  test "configured repo modules are respected" do
    """
    defmodule MyApp.Branches do
      alias MyApp.Conversations.Conversation

      def fetch(slug) do
        OtherRepo.get_by(Conversation, slug: slug)
      end
    end
    """
    |> to_source_file("lib/my_app/branches.ex")
    |> run_context_check(repo_modules: [MyApp.Repo])
    |> refute_issues()
  end

  test "does not report when contexts are not configured" do
    """
    defmodule MyApp.Branches do
      import Ecto.Query
      alias MyApp.Conversations.Conversation

      def query do
        from(c in Conversation, where: c.id == 1)
      end
    end
    """
    |> to_source_file("lib/my_app/branches.ex")
    |> run_check(ContextOwnsSchemaQueries)
    |> refute_issues()
  end

  test "allow owner descendants option permits nested modules" do
    """
    defmodule MyApp.Conversations.Detail do
      import Ecto.Query
      alias MyApp.Conversations.Conversation

      def query do
        from(c in Conversation, where: c.visible)
      end
    end
    """
    |> to_source_file("lib/my_app/conversations/detail.ex")
    |> run_context_check(allow_owner_descendants: true)
    |> refute_issues()
  end

  defp run_context_check(source_file, opts \\ []) do
    opts =
      Keyword.merge(
        [
          contexts: [
            MyApp.Conversations,
            MyApp.Branches,
            MyApp.Runs
          ]
        ],
        opts
      )

    run_check(source_file, ContextOwnsSchemaQueries, opts)
  end
end
