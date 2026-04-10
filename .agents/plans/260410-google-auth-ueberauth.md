# Google Auth With Ueberauth Plan

## Goal

Replace the current email magic-link auth entry points with password-based auth plus Google sign-in via `ueberauth`, while preserving the existing `phx.gen.auth` session and `current_scope` behavior.

## Scope

1. Add `ueberauth` and `ueberauth_google` dependencies plus runtime Google OAuth configuration.
2. Extend user persistence so Google-authenticated users can be found or created safely.
3. Add controller routes for `/auth/google` and `/auth/google/callback` in the public browser scope.
4. Remove the visible magic-link login flow and replace registration/login LiveViews with password + Google entry points.
5. Update tests for password signup/login and Google callback handling.
6. Run `mix precommit` and record the final changelog entry.

## Router placement

- Place Google OAuth controller routes in the existing public `scope "/", AppWeb` with `pipe_through [:browser]`.
- Keep registration and login LiveViews inside the existing `live_session :current_user` block.
- Do not move any authenticated routes out of `live_session :require_authenticated_user` or `:require_active_organization`.

Why:
- OAuth request and callback endpoints need the browser session and `current_scope`, but they must remain reachable before login.
- Registration and login pages already belong to the public auth flow and work with or without an authenticated user.

## Notes

- Google sign-in should only trust accounts with a verified Google email.
- Password registration should stop sending confirmation magic links.
- Existing password update and signed-in session behavior should remain unchanged.
