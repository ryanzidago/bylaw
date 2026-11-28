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
          {Credo.Check.Readability.ImplTrue, []},
          {Credo.Check.Readability.Specs, []},
          {Bylaw.Credo.Check.Elixir.DocBeforeSpec, []},
          {Bylaw.Credo.Check.Elixir.FilterRejectFirst, []},
          {Bylaw.Credo.Check.Elixir.FullyTypedOpts, []},
          {Bylaw.Credo.Check.Elixir.NamedSpecParams, []},
          {Bylaw.Credo.Check.Elixir.NoThen, []},
          {Bylaw.Credo.Check.Elixir.PreferEmptyListChecks, []},
          {Bylaw.Credo.Check.Elixir.PreferBlockIf, []},
          {Bylaw.Credo.Check.Elixir.PreferEnumCount, []},
          {Bylaw.Credo.Check.Elixir.PreferEnumUniqBy, []},
          {Bylaw.Credo.Check.Elixir.PreferListTypeSyntax, []},
          {Bylaw.Credo.Check.Elixir.RejectCount, []},
          {Credo.Check.Warning.UnsafeToAtom, []}
        ],
        disabled: [
          {Credo.Check.Refactor.Nesting, []}
        ]
      }
    }
  ]
}
