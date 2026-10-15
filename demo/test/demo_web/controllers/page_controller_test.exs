defmodule DemoWeb.PageControllerTest do
  use DemoWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)

    assert response =~ "JsFormatter integration demo"
    assert response =~ "Colocated JavaScript, checked at the source"
    assert response =~ ~s(phx-hook="DemoWeb.FormatterDemoLive.FormatterDemo")
  end
end
