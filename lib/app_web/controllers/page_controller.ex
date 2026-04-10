defmodule AppWeb.PageController do
  use AppWeb, :controller

  def home(conn, _params) do
    render(conn, :home, current_scope: conn.assigns[:current_scope])
  end

  def privacy(conn, _params) do
    render(conn, :privacy, current_scope: conn.assigns[:current_scope])
  end

  def terms(conn, _params) do
    render(conn, :terms, current_scope: conn.assigns[:current_scope])
  end
end
