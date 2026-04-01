# Plan: Dashboard Padding Update

## Problem
Dashboard-backed pages need to own their spacing now that the shared dashboard shell no longer adds inner padding. The chat room view also needs a cleaner structure so the header border spans full width and the message input is no longer wrapped in a card-like container.

## Approach
Move page-level padding into each dashboard-backed page, then restructure the chat room view so the header, message list, and input each control their own spacing independently.

## Todos
- Add page-level padding to all `Layouts.dashboard` pages.
- Rework the chat room view so the header border reaches the full width and the input is not wrapped in a card container.
- Run format/compile checks to catch HEEx or layout regressions.

## Notes
- The shared dashboard layout should stay padding-free so pages can align precisely with their own headers and content sections.
