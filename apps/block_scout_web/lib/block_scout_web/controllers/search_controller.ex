defmodule BlockScoutWeb.SearchController do
  use BlockScoutWeb, :controller

  alias BlockScoutWeb.{Controller, SearchView}
  alias Explorer.Chain.Search
  alias Phoenix.View

  def search_results(conn, %{"q" => query, "type" => "JSON"} = params) do
    [paging_options: paging_options] = Search.parse_paging_options(params)

    {search_results, next_page_params} =
      paging_options
      |> Search.joint_search(query)

    next_page_url =
      case next_page_params do
        nil ->
          nil

        next_page_params ->
          search_path(conn, :search_results, Map.delete(next_page_params, "type"))
      end

    items =
      search_results
      |> Enum.with_index(1)
      |> Enum.map(fn {result, _index} ->
        View.render_to_string(
          SearchView,
          "_tile.html",
          result: result,
          conn: conn,
          query: query
        )
      end)

    json(
      conn,
      %{
        items: items,
        next_page_path: next_page_url
      }
    )
  end

  def search_results(conn, %{"type" => "JSON"}) do
    json(
      conn,
      %{
        items: []
      }
    )
  end

  def search_results(conn, %{"q" => query}) do
    render(
      conn,
      "results.html",
      query: query,
      current_path: Controller.current_full_path(conn)
    )
  end

  def search_results(conn, %{}) do
    render(
      conn,
      "results.html",
      query: nil,
      current_path: Controller.current_full_path(conn)
    )
  end
end
