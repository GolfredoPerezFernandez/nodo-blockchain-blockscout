defmodule BlockScoutWeb.Plug.RateLimit do
  @moduledoc """
    Rate limiting
  """
  alias BlockScoutWeb.AccessHelper

  def init(opts), do: opts

  def call(conn, graphql?: true) do
    case AccessHelper.check_rate_limit(conn, graphql?: true) do
      :ok ->
        conn

      true ->
        conn

      _ ->
        AccessHelper.handle_rate_limit_deny(conn, true)
    end
  end

  def call(conn, _opts) do
    case AccessHelper.check_rate_limit(conn) do
      :ok ->
        conn

      :rate_limit_reached ->
        AccessHelper.handle_rate_limit_deny(conn, true)
    end
  end
end
