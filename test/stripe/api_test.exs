defmodule Stripe.APITest do
  use ExUnit.Case

  import Mox

  test "works with 301 responses without issue" do
    {:error, %Stripe.Error{extra: %{http_status: 301}}} =
      Stripe.API.request(%{}, :get, "/", %{}, [])
  end

  test "oauth_request works" do
    verify_on_exit!()

    Stripe.APIMock
    |> expect(:oauth_request, fn method, _endpoint, _body -> method end)

    assert Stripe.APIMock.oauth_request(:post, "www", %{body: "body"}) == :post
  end

  test "oauth_request sets authorization header for deauthorize request" do
    defmodule HackneyMock do
      def request(_, _, headers, _, _) do
        kv_headers =
          headers
          |> Enum.reduce(%{}, fn {k, v}, acc -> Map.put(acc, k, v) end)

        {:ok, 200, headers, Poison.encode!(kv_headers)}
      end
    end

    Application.put_env(:stripity_stripe, :http_module, HackneyMock)

    {:ok, body} = Stripe.API.oauth_request(:post, "deauthorize", %{})
    assert body["Authorization"] == "Bearer sk_test_123"

    {:ok, body} = Stripe.API.oauth_request(:post, "deauthorize", %{}, "1234")
    assert body["Authorization"] == "Bearer 1234"

    {:ok, body} = Stripe.API.oauth_request(:post, "token", %{})
    assert Map.keys(body) |> Enum.member?("Authorization") == false
  end

  test "reads hackney timeout opts from config" do
    # Return request opts as response body
    defmodule HackneyMock do
      def request(_, _, headers, _, opts) do
        kv_opts =
          opts
          |> Enum.reduce(%{}, fn opt, acc ->
            case opt do
              {k, v} ->
                Map.put(acc, k, v)
              _ ->
                Map.put(acc, opt, opt)
            end
          end)

        {:ok, 200, headers, Poison.encode!(kv_opts)}
      end
    end

    Application.put_env(:stripity_stripe, :http_module, HackneyMock)

    {:ok, request_opts} = Stripe.API.request(%{}, :get, "/", %{}, [])
    refute Map.has_key?(request_opts, "connect_timeout")
    refute Map.has_key?(request_opts, "recv_timeout")

    Application.put_env(:stripity_stripe, :hackney_opts, [{:connect_timeout, 1000}, {:recv_timeout, 5000}])

    {:ok, request_opts} = Stripe.API.oauth_request(:post, "token", %{})
    assert request_opts["connect_timeout"] == 1000
    assert request_opts["recv_timeout"] == 5000

    {:ok, request_opts} = Stripe.API.request(%{}, :get, "/", %{}, [])
    assert request_opts["connect_timeout"] == 1000
    assert request_opts["recv_timeout"] == 5000
  end
end
