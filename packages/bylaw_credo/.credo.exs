# This file contains the configuration for Credo and you are probably reading
# this after creating it with `mix credo.gen.config`.
#
# If you find anything wrong or unclear in this file, please report an
# issue on GitHub: https://github.com/rrrene/credo/issues
#
%{
  #
  # You can have as many configs as you like in the `configs:` field.
  configs: [
    %{
      #
      # Run any config using `mix credo -C <name>`. If no config name is given
      # "default" is used.
      #
      name: "default",
      #
      # These are the files included in the analysis:
      files: %{
        #
        # You can give explicit globs or simply directories.
        # In the latter case `**/*.{ex,exs}` will be used.
        #
        included: [
          "lib/",
          "src/",
          "test/",
          "web/",
          "apps/*/lib/",
          "apps/*/src/",
          "apps/*/test/",
          "apps/*/web/"
        ],
        excluded: ["_build/", "deps/", "node_modules/"]
      },
      #
      # Load and configure plugins here:
      #
      plugins: [],
      #
      # If you create your own checks, you must specify the source files for
      # them here, so they can be loaded by Credo before running the analysis.
      #
      requires: [],
      #
      # If you want to enforce a style guide and need a more traditional linting
      # experience, you can change `strict` to `true` below:
      #
      strict: false,
      #
      # To modify the timeout for parsing files, change this value:
      #
      parse_timeout: 5000,
      #
      # If you want to use uncolored output by default, you can change `color`
      # to `false` below:
      #
      color: true,
      #
      # You can customize the parameters of any check by adding a second element
      # to the tuple.
      #
      # To disable a check put `false` as second element:
      #
      #     {Credo.Check.Design.DuplicatedCode, false}
      #
      checks: %{
        enabled: [
          #
          ## Consistency Checks
          #
          {Credo.Check.Consistency.ExceptionNames, []},
          {Credo.Check.Consistency.LineEndings, []},
          {Credo.Check.Consistency.ParameterPatternMatching, []},
          {Credo.Check.Consistency.SpaceAroundOperators, []},
          {Credo.Check.Consistency.SpaceInParentheses, []},
          {Credo.Check.Consistency.TabsOrSpaces, []},
          {Credo.Check.Consistency.MultiAliasImportRequireUse, []},
          {Credo.Check.Consistency.UnusedVariableNames, []},

          #
          ## Design Checks
          #
          # You can customize the priority of any check
          # Priority values are: `low, normal, high, higher`
          #
          {Credo.Check.Design.AliasUsage,
           [priority: :low, if_nested_deeper_than: 2, if_called_more_often_than: 0]},
          {Credo.Check.Design.TagFIXME, []},
          # You can also customize the exit_status of each check.
          # If you don't want TODO comments to cause `mix credo` to fail, just
          # set this value to 0 (zero).
          #
          {Credo.Check.Design.TagTODO, [exit_status: 2]},
          {Credo.Check.Design.SkipTestWithoutComment, []},
          {Bylaw.Credo.Check.Elixir.NoRaise, false},
          {Bylaw.Credo.Check.Elixir.NoPassthroughWrapper, false},
          {Bylaw.Credo.Check.Phoenix.ContextFunctionNaming, false},
          {Bylaw.Credo.Check.Ecto.UseMyAppSchema, false},
          {Bylaw.Credo.Check.Ecto.OwnContextForSchema, [schema_modules: [Bylaw.Schema]]},

          #
          ## Readability Checks
          #
          {Credo.Check.Readability.AliasAs, []},
          {Credo.Check.Readability.AliasOrder, []},
          {Credo.Check.Readability.BlockPipe, []},
          {Credo.Check.Readability.FunctionNames, []},
          {Bylaw.Credo.Check.Elixir.UseMaybeInFunctionName, []},
          {Credo.Check.Readability.ImplTrue, []},
          {Credo.Check.Readability.LargeNumbers, []},
          {Credo.Check.Readability.MaxLineLength, [priority: :low, max_length: 120]},
          {Credo.Check.Readability.ModuleAttributeNames, []},
          {Credo.Check.Readability.ModuleDoc, []},
          {Credo.Check.Readability.ModuleNames, []},
          {Bylaw.Credo.Check.Elixir.AppModuleAcronymCasing, [app_roots: ~w(Bylaw BylawWeb)]},
          {Credo.Check.Readability.MultiAlias, []},
          {Credo.Check.Readability.NestedFunctionCalls, []},
          {Credo.Check.Readability.OneArityFunctionInPipe, []},
          {Credo.Check.Readability.OnePipePerLine, []},
          {Credo.Check.Readability.ParenthesesInCondition, []},
          {Credo.Check.Readability.ParenthesesOnZeroArityDefs, []},
          {Credo.Check.Readability.PipeIntoAnonymousFunctions, []},
          {Credo.Check.Readability.PredicateFunctionNames, []},
          {Credo.Check.Readability.PreferImplicitTry, []},
          {Credo.Check.Readability.RedundantBlankLines, []},
          {Credo.Check.Readability.Semicolons, []},
          {Credo.Check.Readability.SeparateAliasRequire, []},
          {Credo.Check.Readability.SpaceAfterCommas, []},
          {Credo.Check.Readability.StringSigils, []},
          {Credo.Check.Readability.SingleFunctionToBlockPipe, []},
          {Credo.Check.Readability.SinglePipe, []},
          {Credo.Check.Readability.Specs, []},
          {Credo.Check.Readability.StrictModuleLayout, []},
          {Credo.Check.Readability.TrailingBlankLine, []},
          {Credo.Check.Readability.TrailingWhiteSpace, []},
          {Credo.Check.Readability.UnnecessaryAliasExpansion, []},
          {Credo.Check.Readability.VariableNames, []},
          {Credo.Check.Readability.WithCustomTaggedTuple, []},
          {Credo.Check.Readability.WithSingleClause, []},
          {Bylaw.Credo.Check.Elixir.NoThen, []},
          {Bylaw.Credo.Check.Ecto.PipeBasedQueries, false},
          {Bylaw.Credo.Check.Elixir.PreferEmptyListChecks, false},
          {Bylaw.Credo.Check.Elixir.PreferEnumCount, []},
          {Bylaw.Credo.Check.Elixir.PreferEnumUniqBy, []},
          {Bylaw.Credo.Check.Elixir.PreferListTypeSyntax, []},
          {Bylaw.Credo.Check.Elixir.DocBeforeSpec, []},
          {Bylaw.Credo.Check.Ecto.PreferRepoAggregateCount, []},
          {Bylaw.Credo.Check.Ecto.PreferSelectOverRepoAllEnumMap, []},
          {Bylaw.Credo.Check.Elixir.NoParamExtractionInFunctionHead, false},
          {Bylaw.Credo.Check.Elixir.NamedSpecParams, false},
          {Bylaw.Credo.Check.Elixir.FullyTypedOpts,
           [
             excluded_paths: [
               "lib/bylaw/repo.ex",
               "lib/bylaw_web/auth/require_api_key.ex"
             ]
           ]},
          {Bylaw.Credo.Check.Elixir.WithElseClause, []},
          {Bylaw.Credo.Check.Elixir.NoCatchAllInWithElse, false},

          #
          ## Refactoring Opportunities
          #
          {Credo.Check.Refactor.AppendSingleItem, []},
          {Credo.Check.Refactor.Apply, []},
          {Credo.Check.Refactor.CondStatements, []},
          {Credo.Check.Refactor.CondInsteadOfIfElse, false},
          {Credo.Check.Refactor.CyclomaticComplexity, []},
          {Credo.Check.Refactor.DoubleBooleanNegation, []},
          {Credo.Check.Refactor.FilterCount, []},
          {Credo.Check.Refactor.FilterFilter, []},
          {Credo.Check.Refactor.FilterReject, []},
          {Credo.Check.Refactor.FunctionArity, []},
          {Credo.Check.Refactor.IoPuts, []},
          {Credo.Check.Refactor.LongQuoteBlocks, []},
          {Credo.Check.Refactor.MapJoin, []},
          {Credo.Check.Refactor.MapMap, []},
          {Credo.Check.Refactor.MatchInCondition, []},
          {Credo.Check.Refactor.NegatedConditionsInUnless, []},
          {Credo.Check.Refactor.NegatedConditionsWithElse, []},
          {Credo.Check.Refactor.NegatedIsNil, []},
          {Credo.Check.Refactor.Nesting, []},
          {Credo.Check.Refactor.PassAsyncInTestCases, []},
          {Credo.Check.Refactor.RedundantWithClauseResult, []},
          {Credo.Check.Refactor.RejectFilter, []},
          {Credo.Check.Refactor.RejectReject, []},
          {Credo.Check.Refactor.UnlessWithElse, []},
          {Credo.Check.Refactor.UtcNowTruncate, []},
          {Credo.Check.Refactor.WithClauses, []},
          {Bylaw.Credo.Check.Elixir.FilterRejectFirst, []},
          {Bylaw.Credo.Check.Elixir.RejectCount, []},

          #
          ## Warnings
          #
          {Credo.Check.Warning.ApplicationConfigInModuleAttribute, []},
          {Credo.Check.Warning.BoolOperationOnSameValues, []},
          {Credo.Check.Warning.Dbg, []},
          {Credo.Check.Warning.ExpensiveEmptyEnumCheck, []},
          {Credo.Check.Warning.IExPry, []},
          {Credo.Check.Warning.IoInspect, []},
          {Credo.Check.Warning.MissedMetadataKeyInLoggerConfig, []},
          {Credo.Check.Warning.OperationOnSameValues, []},
          {Credo.Check.Warning.OperationWithConstantResult, []},
          {Credo.Check.Warning.RaiseInsideRescue, []},
          {Credo.Check.Warning.SpecWithStruct, []},
          {Credo.Check.Warning.StructFieldAmount, []},
          {Credo.Check.Warning.UnsafeExec, []},
          {Credo.Check.Warning.UnusedEnumOperation, []},
          {Credo.Check.Warning.UnusedFileOperation, []},
          {Credo.Check.Warning.UnusedKeywordOperation, []},
          {Credo.Check.Warning.UnusedListOperation, []},
          {Credo.Check.Warning.UnusedMapOperation, []},
          {Credo.Check.Warning.UnusedPathOperation, []},
          {Credo.Check.Warning.UnusedRegexOperation, []},
          {Credo.Check.Warning.UnusedStringOperation, []},
          {Credo.Check.Warning.UnusedTupleOperation, []},
          {Credo.Check.Warning.WrongTestFilename, []},
          {Bylaw.Credo.Check.Elixir.FloatUsage, []},
          {Bylaw.Credo.Check.Phoenix.UseVerifiedRoutes, []},
          {Bylaw.Credo.Check.Ecto.PreferDateTimeOverDate, false},
          {Bylaw.Credo.Check.Ecto.NamedBinding, [excluded_paths: ["test/", "_test.exs"]]},
          {Bylaw.Credo.Check.Ecto.ErrorChangesetPatternMatch, []},
          {Bylaw.Credo.Check.Elixir.FullySpecifiedStructTypes, []},
          {Bylaw.Credo.Check.Ecto.NoAndInWhere, false},
          {Bylaw.Credo.Check.Elixir.NoEndOfDayTime, [excluded_paths: ["test/", "_test.exs"]]},
          {Bylaw.Credo.Check.PhoenixLiveView.NoInlineAssignInReturnTuple, []},
          {Bylaw.Credo.Check.Elixir.NoResultTupleArgument,
           [excluded_paths: [~r{^lib/bylaw/credo/check/}]]},
          {Bylaw.Credo.Check.Phoenix.NoRepoInController, []},
          {Bylaw.Credo.Check.Ecto.NoRepoPreloadAfterQuery, []},
          {Bylaw.Credo.Check.Ecto.ComposablePreloadQueries, []},
          {Bylaw.Credo.Check.Ecto.NoRepoTransaction, []},
          {Bylaw.Credo.Check.Testing.NoGlobalStateInTests, []},
          {Bylaw.Credo.Check.Testing.NoSetupInTests, [excluded_paths: ["test/support/"]]},
          {Bylaw.Credo.Check.Elixir.NoTryRescue, []},
          {Bylaw.Credo.Check.Elixir.SafeDateTimeComparison, false},
          {Bylaw.Credo.Check.Elixir.NoLowLevelProcessPrimitives, []},
          {Bylaw.Credo.Check.Phoenix.URIDecodeQuery, []}
        ],
        disabled: [
          #
          # Controversial and experimental checks (opt-in, just move the check to `:enabled`
          #   and be sure to use `mix credo --strict` to see low priority checks)
          #
          {Credo.Check.Design.DuplicatedCode, []},
          {Credo.Check.Refactor.ABCSize, []},
          {Credo.Check.Refactor.ModuleDependencies, []},
          {Credo.Check.Refactor.VariableRebinding, []},
          {Credo.Check.Warning.LazyLogging, []},
          {Credo.Check.Warning.LeakyEnvironment, []},
          {Bylaw.Credo.Check.Testing.NoTestsInTestDir, []}
          # {Credo.Check.Warning.UnusedOperation, [{MyMagicModule, [:fun1, :fun2]}]}

          # {Credo.Check.Refactor.MapInto, []},

          #
          # Custom checks can be created using `mix credo.gen.check`.
          #
        ]
      }
    }
  ]
}
