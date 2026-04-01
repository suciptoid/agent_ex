defmodule AppWeb.DashboardLive do
  use AppWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Dashboard")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dashboard
      flash={@flash}
      current_scope={@current_scope}
    >
      <%!-- Dashboard Content --%>
      <div class="flex h-full min-h-0 flex-col p-4 pt-20 sm:px-5 sm:pb-5 sm:pt-20 lg:p-6">
        <div class="space-y-8">
          <%!-- Welcome Section --%>
          <div class="border-b border-gray-200 dark:border-gray-700 pb-6">
            <h1 class="text-3xl font-bold tracking-tight text-gray-900 dark:text-white">
              Welcome back!
            </h1>
            <p class="mt-2 text-lg text-gray-600 dark:text-gray-300">
              {@current_scope.user.email}
            </p>
          </div>

          <%!-- Quick Stats Cards --%>
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <.card>
              <.card_header>
                <.card_title>Total Users</.card_title>
                <.card_description>Registered accounts</.card_description>
              </.card_header>
              <.card_content>
                <p class="text-3xl font-semibold text-gray-900 dark:text-white">1</p>
              </.card_content>
            </.card>

            <.card>
              <.card_header>
                <.card_title>Active Sessions</.card_title>
                <.card_description>Current logins</.card_description>
              </.card_header>
              <.card_content>
                <p class="text-3xl font-semibold text-gray-900 dark:text-white">1</p>
              </.card_content>
            </.card>

            <.card>
              <.card_header>
                <.card_title>Account Status</.card_title>
                <.card_description>Your account health</.card_description>
              </.card_header>
              <.card_content>
                <span class="inline-flex items-center rounded-full bg-green-100 px-2.5 py-0.5 text-sm font-medium text-green-800 dark:bg-green-900 dark:text-green-200">
                  Active
                </span>
              </.card_content>
            </.card>
          </div>

          <%!-- Recent Activity Section --%>
          <.card>
            <.card_header>
              <.card_title>Recent Activity</.card_title>
              <.card_description>Your recent actions and events</.card_description>
            </.card_header>
            <.card_content>
              <div class="flex flex-col items-center justify-center py-12 text-center">
                <.icon name="hero-clock" class="size-12 text-gray-400 mb-4" />
                <p class="text-gray-500 dark:text-gray-400">No recent activity to show.</p>
              </div>
            </.card_content>
          </.card>
        </div>
      </div>
    </Layouts.dashboard>
    """
  end
end
