# Releasing bylaw-ui

Use this checklist to publish a `bylaw-ui` version from a dedicated release
worktree. A release is complete only after the packed artifact passes in an
isolated consumer and the published registry package can be installed.

## Prepare the release

1. Confirm `package.json` contains the intended version.
2. Add the same version and release date to `CHANGELOG.md`.
3. Update README installation or compatibility guidance when the release
   changes it.
4. Confirm the worktree contains only the release changes.

## Verify the package

From `packages/bylaw_ui`:

```sh
bun install --frozen-lockfile
bunx playwright-core install chromium
bun run qa
bun run test:package
bun publish --dry-run
```

`bun run qa` verifies formatting, build output, declarations, type safety, and
the complete test suite. `bun run test:package` packs the package, installs the
tarball into an isolated ESM TypeScript consumer, compiles it, and exercises it
with Node and Chromium.

Run the repository gate from the worktree root:

```sh
scripts/qa.sh
```

Do not publish while any command is failing or while the worktree differs from
the reviewed release commit.

## Publish

After the release commit is merged to `main` and the local checkout is updated:

```sh
cd packages/bylaw_ui
npm whoami
bun publish --access public
```

Create and push the package tag only after the registry accepts the release:

```sh
git tag bylaw-ui-v0.1.0
git push origin bylaw-ui-v0.1.0
```

Replace `0.1.0` with the version being published.

## Verify the registry release

Confirm npm reports the intended version and entrypoints:

```sh
npm view bylaw-ui@0.1.0 version dist-tags exports
```

Then install the registry artifact in a new temporary consumer rather than
reusing the repository build:

```sh
bylaw_ui_smoke_dir="$(mktemp -d)"
cd "$bylaw_ui_smoke_dir"
bun init -y
bun add bylaw-ui@0.1.0 playwright-core@1.62.0
node --input-type=module -e 'await import("bylaw-ui"); await import("bylaw-ui/playwright")'
```

Record the npm package URL, published version, Git tag, and registry smoke-test
result in the GitHub release notes.
