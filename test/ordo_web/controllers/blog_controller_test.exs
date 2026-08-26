defmodule OrdoWeb.BlogControllerTest do
  use OrdoWeb.ConnCase, async: true

  describe "index" do
    test "GET /blog renders the Polish blog list with SEO tags", %{conn: conn} do
      conn = get(conn, ~p"/blog")
      html = html_response(conn, 200)

      assert html =~ "Blog Ordo"
      assert html =~ "Jak zautomatyzować obsługę klienta"
      assert html =~ ~s(<link rel="canonical")
      assert html =~ ~s(hreflang="en")
      assert html =~ ~s(hreflang="x-default")
      assert html =~ "application/ld+json"
    end

    test "GET /en/blog renders the English list", %{conn: conn} do
      html = conn |> get(~p"/en/blog") |> html_response(200)
      assert html =~ "How to Automate E-commerce Customer Support"
      assert html =~ ~s(<html lang="en">)
    end
  end

  describe "show" do
    test "GET /blog/:slug renders the article with BlogPosting JSON-LD", %{conn: conn} do
      html =
        conn
        |> get(~p"/blog/jak-zautomatyzowac-obsluge-klienta-w-e-commerce")
        |> html_response(200)

      assert html =~ "Zacznij od kategoryzacji"
      assert html =~ "BlogPosting"
      assert html =~ ~s(hreflang="pl")
      assert html =~ ~s(hreflang="en")
    end

    test "cross-links to the English translation via hreflang", %{conn: conn} do
      html =
        conn
        |> get(~p"/blog/jak-zautomatyzowac-obsluge-klienta-w-e-commerce")
        |> html_response(200)

      assert html =~ "/en/blog/how-to-automate-ecommerce-customer-support"
    end

    test "unknown slug returns 404", %{conn: conn} do
      conn = get(conn, ~p"/blog/nie-istnieje")
      assert conn.status == 404
    end
  end

  describe "feeds and sitemap" do
    test "GET /blog/feed.xml returns an RSS feed", %{conn: conn} do
      conn = get(conn, ~p"/blog/feed.xml")
      assert response_content_type(conn, :xml) =~ "rss"
      body = response(conn, 200)
      assert body =~ "<rss"
      assert body =~ "Jak zautomatyzować obsługę klienta"
    end

    test "GET /sitemap.xml lists posts in both languages with alternates and lastmod", %{conn: conn} do
      body = conn |> get(~p"/sitemap.xml") |> response(200)
      assert body =~ "<urlset"
      assert body =~ "/blog/jak-zautomatyzowac-obsluge-klienta-w-e-commerce"
      assert body =~ "/en/blog/how-to-automate-ecommerce-customer-support"
      assert body =~ ~s(xhtml:link rel="alternate")
      assert body =~ "<lastmod>2026-08-26</lastmod>"
    end

    test "GET /robots.txt allows crawling and points to the sitemap", %{conn: conn} do
      conn = get(conn, ~p"/robots.txt")
      body = response(conn, 200)
      assert response_content_type(conn, :txt) =~ "text/plain"
      assert body =~ "User-agent: *"
      assert body =~ ~r{Sitemap: https?://\S+/sitemap\.xml}
      assert body =~ "Disallow: /users/"
    end
  end
end
