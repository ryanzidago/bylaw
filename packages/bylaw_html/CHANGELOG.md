# Changelog

## Unreleased

- Add the built-in `Bylaw.HTML.Check.RequireInputAutocomplete` check for
  rendered inputs missing a non-blank `autocomplete` attribute.

## 0.1.0-alpha.1 - 2026-05-12

Initial alpha package release.

- Add the `Bylaw.HTML` entrypoint for validating rendered HTML with explicit checks.
- Add the public `Bylaw.HTML.Check` behaviour and `%Bylaw.HTML.Issue{}` issue shape.
- Add the built-in `Bylaw.HTML.Check.PreferLinkForNavigation` check for rendered
  `phx-click` LiveView navigation sequences on non-link elements.
- Add the built-in `Bylaw.HTML.Check.RequireLinkHref` check for rendered anchors
  missing an `href` attribute.
- Add the built-in `Bylaw.HTML.Check.PreferButtonForAction` check for rendered
  anchors with `phx-click` and placeholder action hrefs.
- Add the built-in `Bylaw.HTML.Check.RequireImageAlt` check for rendered images
  missing an `alt` attribute.
- Add the built-in `Bylaw.HTML.Check.RequireButtonType` check for rendered
  buttons missing a valid `type` attribute.
