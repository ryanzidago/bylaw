%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/"],
        excluded: ["_build/", "deps/"]
      },
      checks: %{
        enabled: [
          {Bylaw.Credo.Check.Elixir.DocBeforeSpec, []},
          {Bylaw.Credo.Check.Elixir.NoThen, []},
          {Bylaw.Credo.Check.Elixir.PreferEmptyListChecks, []},
          {Bylaw.Credo.Check.Elixir.PreferEnumCount, []},
          {Bylaw.Credo.Check.Elixir.PreferEnumUniqBy, []},
          {Bylaw.Credo.Check.Elixir.PreferListTypeSyntax, []}
        ],
        disabled: []
      }
    }
  ]
}
