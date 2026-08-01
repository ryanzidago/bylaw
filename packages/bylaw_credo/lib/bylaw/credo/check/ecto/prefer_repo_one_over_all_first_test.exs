defmodule Bylaw.Credo.Check.Ecto.PreferRepoOneOverAllFirstTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Ecto.PreferRepoOneOverAllFirst

  test "reports Repo.all results passed to List.first" do
    """
    defmodule Example do
      alias MyApp.Repo

      def first(query) do
        one = query |> Repo.all() |> List.first()
        two = Repo.all(query) |> List.first()
        three = List.first(Repo.all(query))
        four = query |> MyApp.Repo.all(prefix: "private") |> List.first()

        {one, two, three, four}
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferRepoOneOverAllFirst)
    |> assert_issues(4)
    |> assert_issues_match([
      %{line_no: 5, trigger: "List.first", message: ~r/Repo\.one/},
      %{line_no: 6, trigger: "List.first", message: ~r/Repo\.one/},
      %{line_no: 7, trigger: "List.first", message: ~r/Repo\.one/},
      %{line_no: 8, trigger: "List.first", message: ~r/Repo\.one/}
    ])
  end

  test "reports Repo.all results passed to Enum.at with index zero" do
    """
    defmodule Example do
      alias MyApp.Repo

      def first(query) do
        one = query |> Repo.all() |> Enum.at(0)
        two = Repo.all(query) |> Enum.at(0)
        three = Enum.at(Repo.all(query), 0)

        {one, two, three}
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferRepoOneOverAllFirst)
    |> assert_issues(3)
    |> assert_issues_match([
      %{line_no: 5, trigger: "Enum.at", message: ~r/Repo\.one/},
      %{line_no: 6, trigger: "Enum.at", message: ~r/Repo\.one/},
      %{line_no: 7, trigger: "Enum.at", message: ~r/Repo\.one/}
    ])
  end

  test "reports Repo.all results passed to hd" do
    """
    defmodule Example do
      alias MyApp.Repo

      def first(query) do
        one = query |> Repo.all() |> hd()
        two = Repo.all(query) |> Kernel.hd()
        three = hd(Repo.all(query))
        four = Kernel.hd(Repo.all(query))

        {one, two, three, four}
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferRepoOneOverAllFirst)
    |> assert_issues(4)
    |> assert_issues_match([
      %{line_no: 5, trigger: "hd", message: ~r/Repo\.one!/},
      %{line_no: 6, trigger: "Kernel.hd", message: ~r/Repo\.one!/},
      %{line_no: 7, trigger: "hd", message: ~r/Repo\.one!/},
      %{line_no: 8, trigger: "Kernel.hd", message: ~r/Repo\.one!/}
    ])
  end

  test "reports realistic ordered queries that load all rows before taking the first" do
    """
    defmodule Accounts do
      import Ecto.Query

      alias MyApp.Accounts.User
      alias MyApp.Repo

      def most_recent_active_user(organization_id) do
        from(user in User, as: :user)
        |> where([user: user], user.organization_id == ^organization_id)
        |> where([user: user], user.active == true)
        |> order_by([user: user], desc: user.last_signed_in_at)
        |> Repo.all()
        |> List.first()
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferRepoOneOverAllFirst)
    |> assert_issue(%{
      line_no: 13,
      trigger: "List.first",
      message: ~r/Ecto\.Query\.first.*Repo\.one/s
    })
  end

  test "allows single-row repo reads and unrelated List.first calls" do
    """
    defmodule Example do
      alias MyApp.Repo

      def first(query, values) do
        one = Repo.one(query)
        two = Repo.one!(query)
        three = Repo.get(User, 123)
        four = Repo.get!(User, 123)
        five = List.first(values)
        six = OtherStore.all(query) |> List.first()
        seven = Repo.all(query)
        eight = Repo.all(query) |> Enum.at(1)
        nine = Repo.all(query) |> Enum.at(-1)
        ten = Enum.at(Repo.all(query), index)
        eleven = hd(values)

        {one, two, three, four, five, six, seven, eight, nine, ten, eleven}
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferRepoOneOverAllFirst)
    |> refute_issues()
  end
end
