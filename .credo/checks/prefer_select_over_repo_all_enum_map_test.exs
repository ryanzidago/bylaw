defmodule Bylaw.Credo.Check.Readability.PreferSelectOverRepoAllEnumMapTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Readability.PreferSelectOverRepoAllEnumMap

  describe "reports issues" do
    test "pipe: query |> Repo.all() |> Enum.map with capture extracting fields" do
      """
      defmodule Example do
        alias MyApp.Repo

        def bad(query) do
          query
          |> Repo.all()
          |> Enum.map(&%{role: &1.role, content: &1.content})
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferSelectOverRepoAllEnumMap)
      |> assert_issues(1)
      |> assert_issues_match([%{trigger: "Enum.map", message: ~r/select/}])
    end

    test "pipe: query |> Repo.all() |> Enum.map with fn extracting fields" do
      """
      defmodule Example do
        alias MyApp.Repo

        def bad(query) do
          query
          |> Repo.all()
          |> Enum.map(fn m -> %{role: m.role, content: m.content} end)
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferSelectOverRepoAllEnumMap)
      |> assert_issues(1)
    end

    test "non-pipe: Enum.map(Repo.all(query), callback)" do
      """
      defmodule Example do
        alias MyApp.Repo

        def bad(query) do
          Enum.map(Repo.all(query), &%{name: &1.name})
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferSelectOverRepoAllEnumMap)
      |> assert_issues(1)
    end

    test "pipe: Repo.all(query) |> Enum.map(callback)" do
      """
      defmodule Example do
        alias MyApp.Repo

        def bad(query) do
          Repo.all(query) |> Enum.map(&%{name: &1.name})
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferSelectOverRepoAllEnumMap)
      |> assert_issues(1)
    end

    test "non-pipe: Enum.map(Repo.all(query, opts), callback)" do
      """
      defmodule Example do
        alias MyApp.Repo

        def bad(query) do
          Enum.map(Repo.all(query, timeout: 5_000), &%{name: &1.name})
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferSelectOverRepoAllEnumMap)
      |> assert_issues(1)
    end

    test "pipe: query |> Repo.all(opts) |> Enum.map(callback)" do
      """
      defmodule Example do
        alias MyApp.Repo

        def bad(query) do
          query |> Repo.all(timeout: 5_000) |> Enum.map(&%{name: &1.name})
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferSelectOverRepoAllEnumMap)
      |> assert_issues(1)
    end

    test "capture accessing a single field" do
      """
      defmodule Example do
        alias MyApp.Repo

        def bad(query) do
          query |> Repo.all() |> Enum.map(& &1.id)
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferSelectOverRepoAllEnumMap)
      |> assert_issues(1)
    end

    test "capture accessing chained fields" do
      """
      defmodule Example do
        alias MyApp.Repo

        def bad(query) do
          query |> Repo.all() |> Enum.map(& &1.profile.name)
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferSelectOverRepoAllEnumMap)
      |> assert_issues(1)
    end

    test "fn accessing nested fields" do
      """
      defmodule Example do
        alias MyApp.Repo

        def bad(query) do
          query |> Repo.all() |> Enum.map(fn r -> {r.first_name, r.last_name} end)
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferSelectOverRepoAllEnumMap)
      |> assert_issues(1)
    end

    test "fn accessing chained fields" do
      """
      defmodule Example do
        alias MyApp.Repo

        def bad(query) do
          query |> Repo.all() |> Enum.map(fn r -> r.profile.name end)
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferSelectOverRepoAllEnumMap)
      |> assert_issues(1)
    end

    test "capture with string-keyed map extracting fields" do
      ~S"""
      defmodule Example do
        alias MyApp.Repo

        def bad(query) do
          query |> Repo.all() |> Enum.map(&%{"role" => &1.role, "content" => &1.content})
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferSelectOverRepoAllEnumMap)
      |> assert_issues(1)
    end

    test "fn with string-keyed map extracting fields" do
      ~S"""
      defmodule Example do
        alias MyApp.Repo

        def bad(query) do
          query |> Repo.all() |> Enum.map(fn m -> %{"role" => m.role, "content" => m.content} end)
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferSelectOverRepoAllEnumMap)
      |> assert_issues(1)
    end

    test "Repo.all with options (prefix)" do
      """
      defmodule Example do
        alias MyApp.Repo

        def bad(query) do
          query |> Repo.all(prefix: "tenant_abc") |> Enum.map(& &1.name)
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferSelectOverRepoAllEnumMap)
      |> assert_issues(1)
    end
  end

  describe "does not report issues" do
    test "callback references the full record bare (capture form)" do
      """
      defmodule Example do
        alias MyApp.Repo

        def ok(query) do
          query |> Repo.all() |> Enum.map(&%{id: &1.id, record: &1})
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferSelectOverRepoAllEnumMap)
      |> refute_issues()
    end

    test "callback references the full record bare (fn form)" do
      """
      defmodule Example do
        alias MyApp.Repo

        def ok(query) do
          query |> Repo.all() |> Enum.map(fn r -> %{id: r.id, record: r} end)
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferSelectOverRepoAllEnumMap)
      |> refute_issues()
    end

    test "Enum.map on Repo.all with opts and bare record in fn form" do
      """
      defmodule Example do
        alias MyApp.Repo

        def ok(query) do
          Enum.map(Repo.all(query, timeout: 5_000), fn r -> %{id: r.id, record: r} end)
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferSelectOverRepoAllEnumMap)
      |> refute_issues()
    end

    test "query |> Repo.all(opts) |> Enum.map with bare record in capture form" do
      """
      defmodule Example do
        alias MyApp.Repo

        def ok(query) do
          query |> Repo.all(timeout: 5_000) |> Enum.map(&%{id: &1.id, record: &1})
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferSelectOverRepoAllEnumMap)
      |> refute_issues()
    end

    test "Enum.map on non-Repo source" do
      """
      defmodule Example do
        def ok(items) do
          items |> Enum.map(& &1.name)
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferSelectOverRepoAllEnumMap)
      |> refute_issues()
    end

    test "Repo.all without Enum.map" do
      """
      defmodule Example do
        alias MyApp.Repo

        def ok(query) do
          Repo.all(query)
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferSelectOverRepoAllEnumMap)
      |> refute_issues()
    end

    test "Enum.map on Repo.all with a function reference" do
      """
      defmodule Example do
        alias MyApp.Repo

        def ok(query) do
          query |> Repo.all() |> Enum.map(&to_dto/1)
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferSelectOverRepoAllEnumMap)
      |> refute_issues()
    end

    test "Enum.map on Repo.all with a module function capture" do
      """
      defmodule Example do
        alias MyApp.Repo

        def ok(query) do
          query |> Repo.all() |> Enum.map(&Map.keys/1)
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferSelectOverRepoAllEnumMap)
      |> refute_issues()
    end

    test "callback passes record to a function call" do
      """
      defmodule Example do
        alias MyApp.Repo

        def ok(query) do
          query |> Repo.all() |> Enum.map(fn r -> transform(r) end)
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferSelectOverRepoAllEnumMap)
      |> refute_issues()
    end

    test "other module's all function" do
      """
      defmodule Example do
        def ok(query) do
          OtherStore.all(query) |> Enum.map(& &1.name)
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferSelectOverRepoAllEnumMap)
      |> refute_issues()
    end

    test "string-keyed map with bare record (capture form)" do
      ~S"""
      defmodule Example do
        alias MyApp.Repo

        def ok(query) do
          query |> Repo.all() |> Enum.map(&%{"id" => &1.id, "record" => &1})
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferSelectOverRepoAllEnumMap)
      |> refute_issues()
    end

    test "string-keyed map with bare record (fn form)" do
      ~S"""
      defmodule Example do
        alias MyApp.Repo

        def ok(query) do
          query |> Repo.all() |> Enum.map(fn r -> %{"id" => r.id, "record" => r} end)
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferSelectOverRepoAllEnumMap)
      |> refute_issues()
    end

    test "non-pipe form with bare record (fn form)" do
      """
      defmodule Example do
        alias MyApp.Repo

        def ok(query) do
          Enum.map(Repo.all(query), fn r -> %{id: r.id, r: r} end)
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferSelectOverRepoAllEnumMap)
      |> refute_issues()
    end

    test "intermediate step between Repo.all and Enum.map" do
      """
      defmodule Example do
        alias MyApp.Repo

        def ok(query) do
          query
          |> Repo.all()
          |> Enum.sort_by(& &1.inserted_at)
          |> Enum.map(& &1.name)
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferSelectOverRepoAllEnumMap)
      |> refute_issues()
    end

    test "capture that calls a function on the record" do
      """
      defmodule Example do
        alias MyApp.Repo

        def ok(query) do
          query |> Repo.all() |> Enum.map(&to_string(&1))
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferSelectOverRepoAllEnumMap)
      |> refute_issues()
    end
  end
end
