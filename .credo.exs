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
          ".credo/checks/",
          "lib/",
          "src/",
          "test/",
          "web/",
          "apps/*/lib/",
          "apps/*/src/",
          "apps/*/test/",
          "apps/*/web/"
        ],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      },
      #
      # Load and configure plugins here:
      #
      plugins: [],
      #
      # If you create your own checks, you must specify the source files for
      # them here, so they can be loaded by Credo before running the analysis.
      #
      requires: [".credo/checks/*.ex"],
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
          {Bylaw.Credo.Check.Design.NoRaise, false},
          {Bylaw.Credo.Check.Design.NoPassthroughWrapper, false},
          {Bylaw.Credo.Check.Design.ContextFunctionNaming, false},
          {Bylaw.Credo.Check.Design.UseBylawSchema, false},
          {Bylaw.Credo.Check.Design.OwnContextForSchema, []},

          #
          ## Readability Checks
          #
          {Credo.Check.Readability.AliasAs, []},
          {Credo.Check.Readability.AliasOrder, []},
          {Credo.Check.Readability.BlockPipe, []},
          {Credo.Check.Readability.FunctionNames, []},
          {Bylaw.Credo.Check.Readability.UseMaybeInFunctionName, []},
          {Credo.Check.Readability.ImplTrue, []},
          {Credo.Check.Readability.LargeNumbers, []},
          {Credo.Check.Readability.MaxLineLength, [priority: :low, max_length: 120]},
          {Credo.Check.Readability.ModuleAttributeNames, []},
          {Credo.Check.Readability.ModuleDoc, []},
          {Credo.Check.Readability.ModuleNames, []},
          {Bylaw.Credo.Check.Readability.AppModuleAcronymCasing, []},
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
          {Bylaw.Credo.Check.Readability.NoThen, []},
          {Bylaw.Credo.Check.Readability.PipeBasedEctoQueries, false},
          {Bylaw.Credo.Check.Readability.PreferEmptyListChecks, false},
          {Bylaw.Credo.Check.Readability.PreferEnumCount, []},
          {Bylaw.Credo.Check.Readability.PreferEnumUniqBy, []},
          {Bylaw.Credo.Check.Readability.PreferListTypeSyntax, []},
          {Bylaw.Credo.Check.Readability.DocBeforeSpec, []},
          {Bylaw.Credo.Check.Readability.PreferRepoAggregateCount, []},
          {Bylaw.Credo.Check.Readability.PreferSelectOverRepoAllEnumMap, []},
          {Bylaw.Credo.Check.Readability.NoParamExtractionInFunctionHead, false},
          {Bylaw.Credo.Check.Readability.NamedSpecParams, false},
          {Bylaw.Credo.Check.Readability.FullyTypedOpts,
           [
             excluded_paths: [
               "lib/bylaw/repo.ex",
               "lib/bylaw_web/auth/require_api_key.ex"
             ]
           ]},
          {Bylaw.Credo.Check.Readability.WithElseClause, []},
          {Bylaw.Credo.Check.Readability.NoCatchAllInWithElse, false},

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
          {Bylaw.Credo.Check.Refactor.FilterRejectFirst, []},
          {Bylaw.Credo.Check.Refactor.NoNestedCase, false},
          {Bylaw.Credo.Check.Refactor.RejectCount, []},

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
          {Bylaw.Credo.Check.Warning.FloatUsage, []},
          {Bylaw.Credo.Check.Warning.UseVerifiedRoutes, []},
          {Bylaw.Credo.Check.Warning.NoRawUUIDPathParams, []},
          {Bylaw.Credo.Check.Warning.PreferDateTimeOverDate, false},
          {Bylaw.Credo.Check.Warning.EctoNamedBinding,
           [excluded_paths: ["test/", "_test.exs"]]},
          {Bylaw.Credo.Check.Warning.ErrorChangesetPatternMatch, []},
          {Bylaw.Credo.Check.Warning.FullySpecifiedStructTypes, []},
          {Bylaw.Credo.Check.Warning.NoAndInEctoWhere, false},
          {Bylaw.Credo.Check.Warning.NoEndOfDayTime, [excluded_paths: ["test/", "_test.exs"]]},
          {Bylaw.Credo.Check.Warning.NoInlineAssignInReturnTuple, []},
          {Bylaw.Credo.Check.Warning.NoResultTupleArgument,
           [excluded_paths: [~r{^\.credo/checks/}]]},
          {Bylaw.Credo.Check.Warning.NoRepoInController, []},
          {Bylaw.Credo.Check.Warning.NoRepoPreloadAfterQuery, []},
          {Bylaw.Credo.Check.Warning.ComposablePreloadQueries, []},
          {Bylaw.Credo.Check.Warning.NoRepoMutationInLoop, []},
          {Bylaw.Credo.Check.Warning.NoRepoTransaction, []},
          {Bylaw.Credo.Check.Warning.NoGlobalStateInTests, []},
          {Bylaw.Credo.Check.Warning.NoSetupInTests, [excluded_paths: ["test/support/"]]},
          {Bylaw.Credo.Check.Warning.NoTryRescue, []},
          {Bylaw.Credo.Check.Warning.SafeDateTimeComparison, false},
          {Bylaw.Credo.Check.Warning.NoLowLevelProcessPrimitives, []},
          {Bylaw.Credo.Check.Warning.URIDecodeQuery, []}
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
          {Bylaw.Credo.Check.Warning.NoTestsInTestDir, []}
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
