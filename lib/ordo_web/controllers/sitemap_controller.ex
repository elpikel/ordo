defmodule OrdoWeb.SitemapController do
  @moduledoc "XML sitemap covering the landing page and every blog post (both languages, with hreflang)."
  use OrdoWeb, :controller

  alias Ordo.Blog

  def index(conn, _params) do
    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, sitemap())
  end

  def robots(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, robots_txt())
  end

  defp robots_txt do
    """
    User-agent: *
    Allow: /
    Disallow: /users/
    Disallow: /inbox
    Disallow: /settings
    Disallow: /demo
    Disallow: /locale/

    Sitemap: #{abs_url(~p"/sitemap.xml")}
    """
  end

  defp sitemap do
    entries = Enum.join([home_entry() | index_entries() ++ post_entries()], "\n")

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">
    #{entries}
    </urlset>
    """
  end

  defp home_entry, do: url_entry(abs_url(~p"/"), [], newest_date())

  defp index_entries do
    alts = Enum.map(Blog.locales(), &%{locale: &1, href: abs_url(index_path(&1))})

    Enum.map(Blog.locales(), fn loc ->
      url_entry(abs_url(index_path(loc)), alts, newest_date(loc))
    end)
  end

  defp post_entries do
    Enum.map(Blog.all(), fn post ->
      alts =
        Blog.locales()
        |> Enum.map(fn loc ->
          case Blog.translation(post, loc) do
            nil -> nil
            p -> %{locale: loc, href: abs_url(post_path(p))}
          end
        end)
        |> Enum.reject(&is_nil/1)

      url_entry(abs_url(post_path(post)), alts, post.date)
    end)
  end

  defp url_entry(loc, alternates, lastmod) do
    links =
      Enum.map_join(alternates, "\n", fn a ->
        ~s(    <xhtml:link rel="alternate" hreflang="#{a.locale}" href="#{a.href}"/>)
      end)

    parts =
      [
        "    <loc>#{loc}</loc>",
        lastmod && "    <lastmod>#{Date.to_iso8601(lastmod)}</lastmod>",
        links != "" && links
      ]
      |> Enum.reject(&(&1 in [nil, false, ""]))
      |> Enum.join("\n")

    "  <url>\n#{parts}\n  </url>"
  end

  defp newest_date(locale) do
    case Blog.list(locale) do
      [%{date: date} | _] -> date
      [] -> nil
    end
  end

  defp newest_date do
    Blog.all() |> Enum.map(& &1.date) |> Enum.max(Date, fn -> nil end)
  end

  defp index_path("en"), do: ~p"/en/blog"
  defp index_path(_), do: ~p"/blog"

  defp post_path(%{locale: "en", slug: slug}), do: ~p"/en/blog/#{slug}"
  defp post_path(%{slug: slug}), do: ~p"/blog/#{slug}"

  defp abs_url(path), do: OrdoWeb.Endpoint.url() <> path
end
