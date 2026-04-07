Problem: The provider dropdown is library-backed now, but it still behaves like a plain select without typeahead search.

Approach: Enable the PUI searchable select mode for the provider picker and add a test that proves the search box is present.

Todos:
- Turn on searchable mode for the provider select.
- Update the provider LiveView test to assert the search UI is rendered.

Notes:
- Keep the underlying provider options source unchanged.
