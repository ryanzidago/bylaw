# Changelog

## Unreleased

- Add `Ecto.UUIDFieldTypes` for explicit UUID field types, and extend
  `StructTypes.validate/3` with opt-in compiled UUID field, primary-key and
  generation-version guards. Reuse `TypeBeforeSchema` for declaration order.

- Add `Bylaw.Credo.StructTypes.validate/2` to require a public `t/0` with
  explicit fields for every supplied compiled struct. It compares parsed
  declarations with actual struct fields, including macro-generated fields,
  and reports missing fields, missing types and unverifiable declarations.

- Add `Bylaw.Credo.Check.Ecto.ExplicitAssociations` to report persisted
  `*_id` fields in explicit `schema` blocks without matching `belongs_to`
  associations. Exemptions use `{SchemaModule, field}` pairs. The check does
  not expand shared schema macros and treats dynamic option values
  conservatively.
- Add `Bylaw.Credo.Check.Elixir.BooleanFieldsIsPrefix`. It reports an Ecto
  `field` or a migration `add` of type `:boolean`, a map or struct key
  typed `boolean()` or `boolean() | nil` inside a typespec attribute, and
  an OpenApiSpex `Schema` property with `type: :boolean`, whenever the name
  does not start with one of `:allowed_prefixes` (`["is_"]` by default).
  The message names the `is_` fix. Predicate functions (ending in `?`) and
  non-literal or `{:array, :boolean}` types are left alone.
- Add `Bylaw.Credo.Check.Elixir.NoTestPathsInDocs`. It reports a `@doc`,
  `@moduledoc` or `@typedoc` whose literal string mentions a path under
  `test/`. Docs say why a thing exists, never where its tests are.
- Add `Bylaw.Credo.Check.Elixir.NoUntranslatedText`, the Elixir counterpart of
  `Bylaw.Credo.Check.HEEx.NoUntranslatedText`. It reports a string literal, an
  interpolated string or a `<>` join containing a letter when it is an argument
  of a configured sink (`:sinks`, `{function, arity, positions}` with an
  optional module; `put_flash/3` by default) or a value assigned to one of
  `:assign_keys` (`:page_title` by default). The message names the text and
  says to build it with gettext. Credo's `disable-for-next-line` exempts a
  text meant literally.
- Add two checks that keep every stored instant a Postgres `timestamp with time
  zone` held as `:utc_datetime_usec`. In a migration, `:utc_datetime`,
  `:utc_datetime_usec`, `:naive_datetime`, `:naive_datetime_usec` and
  `:timestamp` all create a column without a time zone; only `:timestamptz`
  creates one with it.
  - `Bylaw.Credo.Check.Ecto.UseTimestamptzInMigrations` reports `add`,
    `add_if_not_exists` and `modify` with one of those types, `timestamps/1`
    with such a type or with no type (unless `:allow_bare_timestamps`, for a
    Repo with `migration_timestamps: [type: :timestamptz]`), and `execute`
    SQL that types a column or cast as `timestamp` or `timestamp without time
    zone`. `:excluded_paths` and `:ignore_migrations_before` skip migrations
    that have already run.
  - `Bylaw.Credo.Check.Ecto.UtcDatetimeUsecInSchemas` reports a `field` or
    `timestamps/1` of another time type in a `schema` block, including a bare
    `timestamps/1` (which holds `:naive_datetime`) and `@timestamps_opts`.
    `embedded_schema` and `embeds_one`/`embeds_many` blocks are exempt.
    `precision: :second` requires `:utc_datetime` instead.

- Add two design-system checks for HEEx. Each message names the fix.
  - `Bylaw.Credo.Check.HEEx.DesignSystem.NoInlineStyle` reports a `style`
    attribute unless every declaration in it sets a custom property
    (`style={"--progress: #{@percent}%"}`). A style it cannot read, such as
    `style={@style}`, is reported. A string behind `&&`, `||`, `and`, `or` or `if` is read the same way,
    every branch included.
  - `Bylaw.Credo.Check.HEEx.DesignSystem.NoHexColor` reports a hex colour in
    the colour attributes of a tag (`:attributes`, by default `fill`, `stroke`,
    `color`, `bgcolor`, `stop-color`, `flood-color`, `lighting-color` and
    `style`), so `href="#add"` and text such as an order number pass.
- Add `Bylaw.Credo.Check.HEEx.DesignSystem.NoElementStyling` so templates can
  only compose components: it reports every `class` and `style` attribute on a
  raw HTML element in `~H` sigils and `.html.heex` templates, whether the value
  is a literal or an expression. Component and slot tags are left alone, since
  `NoComponentClass` covers components. `:attributes` changes which names count
  as styling. `:ceilings` maps a file path to the number of styling attributes
  that file may still have, so an existing codebase can adopt the check and
  only ever lower the numbers: a file at its ceiling reports nothing, above it
  every attribute is reported, below it the check asks to lower the ceiling,
  and at zero it asks to remove the entry. Exclude the component library's own
  files with Credo's per-check `files` option.

- Add five checks against the common causes of flaky tests. Each message
  names the fix.
  - `Bylaw.Credo.Check.Elixir.NoWallClock` reports reads of the wall clock
    (`DateTime.utc_now`, `DateTime.now`, `NaiveDateTime.utc_now`,
    `Date.utc_today`, `Time.utc_now`, `System.os_time`,
    `System.system_time`, and the `:os`, `:erlang` and `:calendar`
    equivalents) outside the modules in `:allowed_modules` and the files in
    `:allowed_paths`. Monotonic time and `:timer.tc` are allowed.
  - `Bylaw.Credo.Check.Testing.NoUnseededRandomness` reports `:rand.uniform`,
    `:rand.uniform_real`, `:rand.normal`, `:rand.bytes`, `Enum.random`,
    `Enum.shuffle` and `Enum.take_random` in tests and `test/support/`, except
    inside `property`, `check all`, `gen all` and `StreamData` calls.
    `System.unique_integer` is allowed unless listed in `:functions`.
  - `Bylaw.Credo.Check.Testing.NoGlobalStateInAsyncTests` reports, in a
    module with `use SomeCase, async: true`, writes to the application and
    system environment, global Mox mode, `Logger.configure`, a fixed-name
    `Process.register`, named ETS table or `name:` option, and a fixed-key
    `:persistent_term.put`/`erase`.
  - `Bylaw.Credo.Check.Testing.NoLiteralReceiveTimeout` reports a literal
    timeout in `assert_receive` and `refute_receive`, and in the helpers
    listed with their timeout position in `:functions`. A variable, module
    attribute, helper call, `0` and `:infinity` are allowed.
- Widen `Bylaw.Credo.Check.Testing.NoSleepInTests`: it now also reports a
  `receive` with only an `after` clause (a sleep written differently) and
  checks `test/support/` as well as `*_test.exs` files, configurable with
  `:included_paths` and `:excluded_paths`. A sleep of `:infinity` is allowed.

- Widen `Bylaw.Credo.Check.Ecto.NamedBinding` to report positional bindings
  anywhere in a query pipeline, such as `from(e in Entry, as: :entry) |>
  where([e], ...)` or a later `|> select([e], ...)`, and in direct calls such
  as `where(query, [e], ...)` and `join(query, :inner, [e], ...)`. Before, it
  only looked at a clause piped from a schema or a bare variable. Named
  bindings and `[{^name, x}]` stay allowed.
- Fix `Bylaw.Credo.Check.Ecto.PipeBasedQueries` so `prefix:` in `from/2` is
  allowed next to `as:` and `hints:`: a source prefix has no pipe equivalent.

- Add `Bylaw.Credo.Check.Phoenix.NoRepoInWeb` to keep database access out of
  the web layer. In files under `:paths` (default `["_web/"]`, never
  `_test.exs`) it reports any call on a module whose last segment is `Repo`,
  `import Ecto.Query`, `alias Ecto.Query` and calls on `Ecto.Query`, so
  LiveViews, components, controllers and plugs call context or core functions
  instead. `Ecto.Changeset` stays allowed. `:excluded_paths` skips files.

- Add `Bylaw.Credo.Check.Ecto.NoRepoInLoop` to report N+1 queries: a repo
  call inside a function given to `Enum`, `Stream` or `Task.async_stream`, or
  inside a `for` comprehension's body, filters and later generators. It
  follows the module's own functions that call the repo. `:repo_modules`
  (default: any module ending in `Repo`), `:loop_modules`, `:loop_functions`
  (for an application's own iterators), `:included_paths` (default
  `["lib/"]`) and `:excluded_paths` configure it.

- Fix `Bylaw.Credo.Check.Testing.NoDescribeBlocks` so a whole-module import of
  a non-ExUnit module, such as `import Phoenix.LiveViewTest`, no longer stops
  `describe` blocks from being reported in a test module that uses
  `ExUnit.Case` or a case template. Only an explicit
  `import Module, only: [describe: 2]` still marks `describe` as non-ExUnit
  there.
- Add `Bylaw.Credo.Check.Elixir.NoComments` to forbid `#` comments in Elixir
  files and `<%!-- --%>` / `<!-- -->` comments in `~H` sigils and `.html.heex`
  templates, so lasting reasons go into `@moduledoc`, `@doc` or `@typedoc`.
  Tool directives listed in `:allowed_directives` (default `["credo:"]`) and a
  first-line shebang are allowed.
- Add `Bylaw.Credo.Check.Testing.HTTPStubsOnlyInClientTests` to keep HTTP stub
  calls and imports (`Req.Test` by default, configurable with `:modules`) in
  the HTTP clients' own tests (`:allowed_paths`, by default any
  `integrations/` directory under `test/`), so other tests expect on the
  integration's behaviour mock.
- Add `Bylaw.Credo.Check.Elixir.NetworkOnlyInIntegrations` to keep calls to
  HTTP, socket and email delivery libraries (`Req`, `Finch`, `Mint`,
  `HTTPoison`, `Tesla`, `:httpc`, `:hackney`, `Swoosh` adapters and mailers,
  `:gen_tcp.connect`, `:ssl.connect`) inside the integration layer. It resolves
  aliases; `:allowed_paths`, `:modules`, `:allowed_modules` and `:functions`
  configure it.
- Add `Bylaw.Credo.Check.Elixir.PreferStructOverMapType` to report closed
  map types with literal atom keys, such as `%{id: integer(), name: String.t()}`,
  in `@type`, `@typep`, `@opaque`, `@spec`, `@callback` and `@macrocallback`,
  and suggest a struct with `@enforce_keys` and a `t()` type instead. Maps with
  non-literal keys and struct types are not reported. `:min_keys` (default `2`)
  and `:excluded_paths` tune it.
- Add `Bylaw.Credo.Check.HEEx.NoUntranslatedText` to report literal readable
  text in `~H` sigils and `.html.heex` templates: text nodes with a letter, and
  letters in user-visible attributes (`alt`, `title`, `placeholder`,
  `aria-label`, `aria-description`, `label`, `phx-disable-with`, configurable
  with `:visible_attributes`) and in the `value` of submit, button and reset
  inputs. `Bylaw.Credo.Heex.Text` tokens now carry their `line_end`.
- Add `Bylaw.Credo.Check.HEEx.DesignSystem.NoArbitraryValues` to forbid
  Tailwind arbitrary values such as `w-[430px]` and arbitrary properties in
  HEEx class attributes, including string literals in dynamic `class={...}`
  expressions. Arbitrary variants and CSS variable shorthand are allowed.
- Add `Bylaw.Credo.Check.HEEx.DesignSystem.PreferComponentOverTag` to report
  raw HTML tags, such as `<button>` or `<input>`, that the design system renders
  through a component. The `:tags` option maps each tag to its component; the
  component modules are excluded with Credo's per-check `files` param.
- Add `Bylaw.Credo.Check.Testing.NoSleepInTests` to report `Process.sleep/1`
  and `:timer.sleep/1` in test files, which make tests slow and flaky.
- Add `Bylaw.Credo.Check.HEEx.RequireFormFieldIdOrName` to require native
  `input`, `select` and `textarea` tags to carry an `id` or a `name`, which
  Chrome otherwise reports as a DevTools issue on every page change.
- Add `Bylaw.Credo.Check.HEEx.NoRawSVG` to discourage raw SVG markup in HEEx
  templates and direct custom SVGs into dedicated component modules.
- Add `Bylaw.Credo.Check.HEEx.DesignSystem.NoComponentClassAttr` to forbid
  `class` and `*_class` attribute declarations on HEEx function components, so
  renaming the attribute cannot sidestep its call-site counterpart. Components
  whose class attribute is their documented interface can be listed in
  `:excluded_components`.
- Add `Bylaw.Credo.Check.HEEx.DesignSystem.NoComponentClass` to forbid class
  attributes on HEEx function components, so components expose named props
  instead of being restyled by their callers. Components whose class attribute
  is their documented interface can be listed in `:excluded_components`.
- Add `Bylaw.Credo.Check.Ecto.TypeBeforeSchema` to require `@type`, `@typep`
  and `@opaque` definitions to appear before a module's Ecto `schema` or
  `embedded_schema` block.
- Add `Bylaw.Credo.Check.Testing.RequireAsyncTests` to require test cases to
  run with `async: true`, or to carry an explanatory comment when they cannot.

- Fix `Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValues` to report accurate
  line, column, scope, and trigger information for tagged-tuple violations.
- Add
  `Bylaw.Credo.Check.PhoenixLiveView.RequireExplicitConnectionStateHandlingInMount`
  to require explicit connected and disconnected lifecycle delegation in
  LiveView `mount/3` clauses.
- Remove `Bylaw.Credo.Check.Elixir.SafeDateTimeComparison`; Elixir compiler
  warnings cover statically known date/time struct comparisons, while the
  check could not reliably infer types for fields and variables.

## 0.4.0 - 2026-08-06

- Add `Bylaw.Credo.Plugin.DisableForNextDefinition` for AST-ranged suppression
  of named or all Credo checks within the next `def` or `defp` clause. Require
  Credo 1.7.16 or newer for exact definition-range token metadata and supported
  Elixir compiler compatibility.

## 0.3.1 - 2026-08-06

- Add `Bylaw.Credo.Check.Ecto.PreferOrderByOverRepoAllEnumSort` to discourage
  sorting `Repo.all` results in memory instead of using `order_by`.

## 0.3.0 - 2026-08-06

- Update `Bylaw.Credo.Check.Elixir.SafeDateTimeComparison` to ignore direct
  date/time comparisons anywhere inside Ecto query expressions.
- Add `Bylaw.Credo.Check.HEEx.DesignSystem.NoArbitrarySpacing` to discourage
  raw pixel spacing values in static HEEx and HTML class and style attributes.
- Add `Bylaw.Credo.Check.HEEx.NoIndirectAssignAccess` to discourage indirect
  access to the special HEEx `assigns` variable.
- Add `Bylaw.Credo.Check.Elixir.NoRemoteCallsInModuleAttributes` to avoid
  application and dependency calls that create compile-time dependencies from
  module attributes while allowing literals and standard-library calls.
- Add `Bylaw.Credo.Check.PhoenixLiveView.RequireFunctionComponentAttrs` to
  require explicit `attr` and `slot` contracts for HEEx function components
  while excluding LiveView `render/1` page assigns.
- Add `Bylaw.Credo.Check.Ecto.PreferRepoOneOverAllFirst` to report queries
  that load every matching row with `Repo.all` before taking the first result
  with `List.first`, `Enum.at(0)`, or `hd`.
- Add `Bylaw.Credo.Check.Ecto.NoDataChangesInSchemaMigrations` to keep Ecto
  schema migrations focused on DDL and direct row mutations in reviewed,
  resumable data-migration scripts or release tasks.
- Add `Bylaw.Credo.Check.Testing.PreferSelectorAssertionsForHtml` to discourage
  brittle test comparisons against serialized HTML attribute order.
- Update `Bylaw.Credo.Check.Testing.NoGlobalStateInTests` to recommend stable
  environment-specific configuration.
- Add `Bylaw.Credo.Check.Elixir.PreferBlockIf` to require block syntax for
  local and qualified Kernel `if` expressions.
- Add `Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValues` to require complex
  tagged-tuple values to be bound to variables.
- Add `Bylaw.Credo.Check.Testing.NoDescribeBlocks` to require descriptive
  standalone tests and focused test files instead of `describe` blocks.

## 0.2.0 - 2026-07-27

- Add `Bylaw.Credo.Check.Ecto.ContextOwnsSchemaQueries` to enforce configured
  Phoenix context ownership for Ecto schema query and Repo CRUD logic.
- Support HEEx checks with the tokenizer module used by Phoenix LiveView 1.2.

## 0.1.1 - 2026-05-13

- Add the `Bylaw.Credo.Check.HEEx.PreferLinkForNavigation` check for HEEx
  `phx-click` navigation handlers on non-link tags and components.

## 0.1.0 - 2026-05-11

Initial package release.

- Add custom Credo checks under `Bylaw.Credo.Check`.
- Add checks for common Elixir, Ecto, Phoenix, test, and project-style
  constraints.
