# Sidebar Mobile Layout Fix

Problem:
The dashboard sidebar currently translates off-screen on small viewports but still occupies inline width in the flex layout, leaving a blank column and shrinking the content area.

Approach:
- Make the sidebar fixed/off-canvas on small screens so it no longer reserves content width.
- Keep the desktop sidebar inline with persisted collapsed width.
- Add a mobile-only floating trigger to reopen the sidebar when auto-collapsed.
- Verify with browser checks and existing project validation.
