# Legacy browser extension disabled

The old root-level extension was removed because it used the legacy native host
name, static `<all_urls>` content scripts and secret-bearing v1 flows.

Use `desktop/browser_extension/` for the Native Messaging v2 MVP. That extension
is Chrome/Edge MV3 only and currently exposes safe host/app status plus
`queryCredentials`/`revealForFill` protocol errors; it does not read, reveal,
store or fill vault credentials.
