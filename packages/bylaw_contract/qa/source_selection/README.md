# Explicit source selection

`Bylaw.Contract.SourceSelection.select(before_files, after_files)` accepts two
maps of source paths to Elixir source strings. It returns `{:ok, MapSet.t(MFA)}`
or `{:error, reasons}`. Use successful current MFAs with `Contract.start/2`'s
`only:` option. Never turn an error into `only: []`: unresolved input is not an
assessed empty scope. Source loading, Git history, application discovery, and
fallback policy belong to the caller.

The API compares authored source; it does not compute transitive impact through
callers, remote dependencies, or configuration. It does not invoke Git, read
files, compile source, expand macros, or evaluate expressions. Elixir parsing
and static module-name construction create atoms, so inputs must be trusted
project source. New static module names work before compilation.

## Supported mapping

- Direct alias-named Elixir modules with direct `def` and `defp` definitions.
- Body, head, guard, visibility, and matching spec changes select the entire
  current function. All current default-argument arities are included; unrelated
  arities with the same name are excluded.
- Removing a clause selects the surviving function. Removed functions have no
  current target. Renames select the new current identity.
- Formatting, comments, and location-independent file moves do not select
  unchanged functions. Literal documentation changes are ignored.
- Each definition and spec retains its ordered lexical prefix. Moving a
  definition across literal attribute assignments, or a spec across aliases,
  selects the affected function even when the module's overall context matches.
- Nested static modules without other enclosing module context retain preceding
  implicit nested aliases. Reordering sibling modules can select functions whose
  inherited aliases change. Selection is conservative when a lexical prefix
  changes: it need not prove that each function uses every prefix declaration.

## Explicit unresolved cases

Changes to shared module context, including local/remote type declarations or
aliases, return `unsupported_module_context`. This includes additions/deletions
of modules carrying such context; type dependency propagation is not inferred.
Unchanged literal attributes, static aliases, and type declarations may be
retained while direct function changes are mapped.

Conditional or generated definitions, `use`, `require`, `import`, executable
module statements, compile callbacks, and executable documentation attributes
return `unsupported_definition_context`, even when unchanged. Executable outer
source returns `unsupported_outer_context`. Nested modules with other enclosing
context return `unsupported_nested_context`; this avoids guessing alias expansion
or inherited compile-time effects. Dynamic modules/functions, duplicate module
identities, and malformed source return explicit reasons. `__DIR__`, `__ENV__`,
and `__CALLER__` return `location_sensitive_source`. Quoted code and unquote forms
return `unsupported_quoted_source`. These limitations are checked before a
successful selection can escape; success never contains a partial inventory.

Widening this subset requires tests against independently compiled behavior,
including unchanged unsupported source and source movement. Existing compiled
oracles demonstrate changed attribute values and nested implicit alias targets.
The 22 acceptance tests also cover default/spec arities, exact current identities,
side-effect-free parsing, callback/quote rejection, and explicit unresolved results.

## Approved repository probes

`probe.exs` reads approved source files and edits strings in memory. It never
modifies or compiles the external source. These are focused source-boundary probes,
not full external application test suites.

| Repository | Revision | Successful edit | Unresolved context |
| --- | --- | --- | --- |
| Ecto | `11784f821a1bb0eedeee59583e311d836cb39ee1` | `Ecto.Repo.Assoc.query/4` empty-list body | `Ecto.UUID` uses `Ecto.Type` |
| Livebook | `f18f2035bac89d6c08497f5f2d7e7c4f56e80716` | `Livebook.Utils.Time.duration_in_words/1` guard | delta operation module imports Kernel |

Both probes verified exact changed MFAs, empty unchanged/moved scope, and explicit
unresolved results for unchanged unsupported context. Raw results and source
SHA-256 hashes are retained in `ecto.json` and `livebook.json`. Run from the
contract package with Elixir 1.20.2 / OTP 29:

```sh
mise exec -- mix run qa/source_selection/probe.exs ecto /path/to/ecto qa/source_selection/ecto.json
mise exec -- mix run qa/source_selection/probe.exs livebook /path/to/livebook qa/source_selection/livebook.json
```

The diff-scope QA adapter delegates source comparison to this API. Its Git and
formatter code remains exploratory caller-side orchestration. Historical timing
artifacts describe their recorded implementation revisions and are not new
measurements of this source mapper.
