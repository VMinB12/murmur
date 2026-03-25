defmodule MurmurWeb.PageController do
  use MurmurWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
