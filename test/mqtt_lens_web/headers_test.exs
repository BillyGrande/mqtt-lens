defmodule MqttLensWeb.HeadersTest do
  @moduledoc """
  Web-security response headers on every response type of the main endpoint
  (ml-1a7.2, criterion 1), the request body limit and no multipart
  (ml-1a7.1.7), and the encrypted session cookie (ml-1a7.1.8).

  Specs: features/web-security.md (Response headers, Request limits),
  features/sessions.md.
  """
  use MqttLensWeb.ConnCase, async: true

  @fixed_headers %{
    "strict-transport-security" => "max-age=63072000; includeSubDomains",
    "x-content-type-options" => "nosniff",
    "referrer-policy" => "no-referrer",
    "cross-origin-opener-policy" => "same-origin",
    "cross-origin-resource-policy" => "same-origin",
    "permissions-policy" => "camera=(), microphone=(), geolocation=()"
  }

  @body_limit 16 * 1024

  defp header_values(headers, name) do
    for {key, value} <- headers, String.downcase(key) == name, do: value
  end

  defp assert_security_headers(headers) do
    for {name, expected} <- @fixed_headers do
      assert header_values(headers, name) == [expected],
             "expected exactly one #{name}: #{expected}, got #{inspect(header_values(headers, name))}"
    end

    assert [csp] = header_values(headers, "content-security-policy"),
           "expected exactly one content-security-policy header"

    assert_csp(csp)

    assert header_values(headers, "access-control-allow-origin") == [],
           "no CORS headers are allowed"
  end

  defp assert_csp(csp) do
    directives =
      csp
      |> String.split(";")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn directive ->
        [name | sources] = String.split(directive, ~r/\s+/)
        {name, sources}
      end)

    names = Enum.map(directives, &elem(&1, 0))
    assert names == Enum.uniq(names), "duplicate CSP directive in: #{csp}"

    directives = Map.new(directives)
    host = MqttLensWeb.Endpoint.host()

    expected = %{
      "default-src" => ["'none'"],
      "script-src" => ["'self'"],
      "style-src" => ["'self'"],
      "img-src" => ["'self'", "data:"],
      "connect-src" => ["'self'", "wss://" <> host],
      "font-src" => ["'self'"],
      "base-uri" => ["'none'"],
      "frame-ancestors" => ["'none'"]
    }

    assert Enum.sort(Map.keys(directives)) ==
             Enum.sort(["form-action" | Map.keys(expected)]),
           "CSP directives differ from web-security.md: #{csp}"

    for {name, sources} <- expected do
      assert directives[name] == sources,
             "CSP #{name}: expected #{inspect(sources)}, got #{inspect(directives[name])}"
    end

    assert ["'self'", keycloak] = directives["form-action"],
           "CSP form-action must be 'self' plus one https Keycloak origin: #{csp}"

    assert keycloak =~ ~r{\Ahttps://[A-Za-z0-9.-]+(:\d+)?\z},
           "CSP form-action Keycloak origin must be an exact https origin: #{keycloak}"
  end

  defp html_conn(conn), do: put_req_header(conn, "accept", "text/html")

  describe "HTML response" do
    test "GET / has every security header and Cache-Control: no-store", %{conn: conn} do
      conn = conn |> html_conn() |> get(~p"/")

      assert html_response(conn, 200)
      assert_security_headers(conn.resp_headers)
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end
  end

  describe "static asset response" do
    test "a digested (vsn) asset has every security header and is immutable", %{conn: conn} do
      conn = get(conn, "/images/logo.svg?vsn=d")

      assert conn.status == 200
      assert_security_headers(conn.resp_headers)

      assert get_resp_header(conn, "cache-control") == [
               "public, max-age=31536000, immutable"
             ]
    end

    test "a non-digested asset has every security header and is not immutable", %{conn: conn} do
      conn = get(conn, "/robots.txt")

      assert conn.status == 200
      assert_security_headers(conn.resp_headers)

      for value <- get_resp_header(conn, "cache-control") do
        refute value =~ "immutable"
      end
    end
  end

  describe "404 response" do
    test "an unknown path has every security header and Cache-Control: no-store",
         %{conn: conn} do
      assert {404, headers} = sent_response(fn -> conn |> html_conn() |> get("/no-such-page") end)

      assert_security_headers(headers)
      assert header_values(headers, "cache-control") == ["no-store"]
    end

    test "a missing file under a static path has every security header", %{conn: conn} do
      assert {404, headers} =
               sent_response(fn -> conn |> html_conn() |> get("/images/missing.svg") end)

      assert_security_headers(headers)
      assert header_values(headers, "cache-control") == ["no-store"]
    end
  end

  describe "error responses" do
    test "400 (query string that is not UTF-8) has every security header", %{conn: conn} do
      assert {400, headers} = sent_response(fn -> conn |> html_conn() |> get("/?a=%FF") end)

      assert_security_headers(headers)
      assert header_values(headers, "cache-control") == ["no-store"]
    end

    test "413 (body too large) has every security header", %{conn: conn} do
      assert {413, headers} = sent_response(fn -> post_form(conn, @body_limit + 1) end)

      assert_security_headers(headers)
      assert header_values(headers, "cache-control") == ["no-store"]
    end

    test "415 (multipart body) has every security header", %{conn: conn} do
      assert {415, headers} = sent_response(fn -> post_multipart(conn) end)

      assert_security_headers(headers)
      assert header_values(headers, "cache-control") == ["no-store"]
    end
  end

  describe "request body limit (16 KiB)" do
    test "a urlencoded body of exactly 16 KiB passes the parser", %{conn: conn} do
      # No POST route exists, so a body that passes Plug.Parsers ends in a 404.
      assert {404, _headers} = sent_response(fn -> post_form(conn, @body_limit) end)
    end

    test "a urlencoded body of 16 KiB + 1 byte is refused with 413", %{conn: conn} do
      assert {413, _headers} = sent_response(fn -> post_form(conn, @body_limit + 1) end)
    end

    test "a multipart body is refused with 415 (no uploads)", %{conn: conn} do
      assert {415, _headers} = sent_response(fn -> post_multipart(conn) end)
    end
  end

  describe "session cookie" do
    test "the session cookie is encrypted, not only signed", %{conn: conn} do
      conn = conn |> html_conn() |> get(~p"/")

      assert html_response(conn, 200)
      assert map_size(conn.resp_cookies) > 0, "GET / must set the session cookie"

      for {name, %{value: value}} <- conn.resp_cookies do
        plain_parts =
          value
          |> String.split(".")
          |> Enum.flat_map(fn part ->
            case Base.url_decode64(part, padding: false) do
              {:ok, decoded} -> [decoded]
              :error -> []
            end
          end)

        refute Enum.any?(plain_parts, &String.contains?(&1, "_csrf_token")),
               "cookie #{name} shows the session content in clear text"
      end
    end
  end

  # Status and headers of the response that the endpoint sent. Phoenix sends
  # a 404 for an unknown route without a raise; for other errors it sends the
  # error page and then raises again.
  defp sent_response(fun) do
    conn = fun.()
    {conn.status, conn.resp_headers}
  rescue
    exception ->
      receive do
        {ref, {status, headers, _body}} when is_reference(ref) -> {status, headers}
      after
        0 -> flunk("no response sent before: " <> Exception.message(exception))
      end
  end

  defp post_form(conn, size) do
    body = "a=" <> String.duplicate("x", size - 2)
    assert byte_size(body) == size

    conn
    |> html_conn()
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> post("/", body)
  end

  defp post_multipart(conn) do
    boundary = "mqttlensboundary"

    body =
      Enum.join(
        [
          "--#{boundary}",
          ~s(Content-Disposition: form-data; name="file"; filename="a.txt"),
          "Content-Type: text/plain",
          "",
          "hello",
          "--#{boundary}--",
          ""
        ],
        "\r\n"
      )

    conn
    |> html_conn()
    |> put_req_header("content-type", "multipart/form-data; boundary=#{boundary}")
    |> post("/", body)
  end
end
