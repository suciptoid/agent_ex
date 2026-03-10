# Dashboard Layout Update Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Update dashboard layout so base width equals screen height, content area uses h-full with overflow-y auto, and sidebar uses h-full with flex layout.

**Architecture:** Modify the `dashboard/1` function in `layouts.ex` to restructure the flex container. The outer container will use viewport height for width calculation, the content area will scroll vertically, and sidebar will maintain full height with flex column layout.

**Tech Stack:** Phoenix LiveView, Tailwind CSS, HEEx templates

---

### Task 1: Update Dashboard Layout Structure

**Files:**
- Modify: `lib/app_web/components/layouts.ex:188-328`

**Step 1: Update the outer dashboard container**

Change the dashboard layout wrapper to set width equal to viewport height using `w-[100vh]` or similar approach. Update the container structure:

```elixir
def dashboard(assigns) do
  ~H"""
  <div
    id="dashboard-layout"
    class="h-screen flex flex-col bg-background overflow-hidden"
    phx-hook=".SidebarState"
  >
```

**Step 2: Update the flex shell container**

Modify the flex container that holds sidebar and content:

```elixir
      <%!-- App Shell: Flex container for sidebar + content --%>
      <div class="flex flex-1 min-h-0">
```

**Step 3: Update the sidebar structure**

Change sidebar to use `h-full` with flex layout:

```elixir
        <%!-- Sidebar --%>
        <aside class={[
          "h-full bg-base border-r border-border transition-all duration-300 ease-in-out flex flex-col",
          "w-64 flex-shrink-0",
          @sidebar_collapsed && "-translate-x-full lg:w-0 lg:border-0 lg:overflow-hidden",
          !@sidebar_collapsed && "translate-x-0"
        ]}>
          <div class="flex flex-col h-full overflow-hidden">
```

**Step 4: Update the main content area**

Modify the main content to use `h-full` with overflow handling:

```elixir
        <%!-- Main Content --%>
        <main class="flex-1 min-w-0 h-full overflow-x-hidden overflow-y-auto">
          <div class="p-4 sm:p-6 lg:p-8">
            {render_slot(@inner_block)}
          </div>
        </main>
```

**Step 5: Verify the changes compile**

Run: `mix compile`
Expected: Compilation succeeds without errors

**Step 6: Test in browser**

Run: `mix phx.server`
Expected: Dashboard displays with proper layout - sidebar full height, content scrollable vertically

**Step 7: Commit**

```bash
git add lib/app_web/components/layouts.ex
git commit -m "feat: update dashboard layout with h-full and overflow handling"
```

---

## Summary of Changes

| Component | Before | After |
|-----------|--------|-------|
| Dashboard wrapper | `min-h-screen flex flex-col` | `h-screen flex flex-col overflow-hidden` |
| App shell | `flex flex-1` | `flex flex-1 min-h-0` |
| Sidebar | `fixed lg:relative z-30 h-[calc(100vh-60px)]` | `h-full flex flex-col` |
| Main content | `flex-1 min-w-0` with inner `max-w-7xl` | `flex-1 min-w-0 h-full overflow-x-hidden overflow-y-auto` |

## Key Tailwind Classes Used

- `h-screen` - Full viewport height
- `h-full` - Full height of parent container
- `overflow-hidden` - Hide overflow on outer container
- `overflow-x-hidden` - Prevent horizontal scroll on content
- `overflow-y-auto` - Enable vertical scrolling on content
- `min-h-0` - Allow flex children to shrink below content size
- `flex flex-col` - Flex column layout for sidebar