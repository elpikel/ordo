defmodule OrdoWeb.BlogController do
  @moduledoc """
  Serves the static blog. The locale comes from the URL (`/blog` = pl,
  `/en/blog` = en) so both language versions are independently crawlable, each
  with a canonical URL and `hreflang` alternates pointing at the other.
  """
  use OrdoWeb, :controller

  alias Ordo.Blog

  # Full-page HTML documents (BlogHTML renders <html>…</html> itself).
  plug :put_root_layout, html: false

  def index(conn, _params) do
    locale = blog_locale(conn)
    Gettext.put_locale(OrdoWeb.Gettext, locale)
    posts = Blog.list(locale)

    render(conn, :index,
      page_title: gettext("Ordo blog"),
      description: gettext("Practical notes on automating e-commerce customer support."),
      locale: locale,
      posts: posts,
      canonical: abs_url(index_path(locale)),
      alternates: index_alternates(locale),
      feed_url: abs_url(feed_path(locale)),
      jsonld: index_jsonld(locale)
    )
  end

  def show(conn, %{"slug" => slug}) do
    locale = blog_locale(conn)
    Gettext.put_locale(OrdoWeb.Gettext, locale)

    case Blog.get(locale, slug) do
      nil ->
        conn
        |> put_status(:not_found)
        |> text(gettext("Post not found."))

      post ->
        render(conn, :show,
          post: post,
          canonical: abs_url(post_path(post)),
          alternates: show_alternates(post),
          feed_url: abs_url(feed_path(locale)),
          jsonld: article_jsonld(post)
        )
    end
  end

  def feed(conn, _params) do
    locale = blog_locale(conn)

    conn
    |> put_resp_content_type("application/rss+xml")
    |> send_resp(200, rss(locale, Blog.list(locale)))
  end

  ## Locale + paths

  defp blog_locale(conn), do: if(String.starts_with?(conn.request_path, "/en/"), do: "en", else: "pl")

  defp index_path("en"), do: ~p"/en/blog"
  defp index_path(_), do: ~p"/blog"

  defp feed_path("en"), do: ~p"/en/blog/feed.xml"
  defp feed_path(_), do: ~p"/blog/feed.xml"

  defp post_path(%{locale: "en", slug: slug}), do: ~p"/en/blog/#{slug}"
  defp post_path(%{slug: slug}), do: ~p"/blog/#{slug}"

  defp abs_url(path), do: OrdoWeb.Endpoint.url() <> path

  ## hreflang alternates

  defp index_alternates(current) do
    Enum.map(Blog.locales(), fn loc ->
      %{locale: loc, href: abs_url(index_path(loc)), current?: loc == current}
    end)
  end

  defp show_alternates(post) do
    Blog.locales()
    |> Enum.map(fn loc ->
      case Blog.translation(post, loc) do
        nil -> nil
        p -> %{locale: loc, href: abs_url(post_path(p)), current?: loc == post.locale}
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  ## JSON-LD (structured data)

  defp index_jsonld(locale) do
    Jason.encode!(
      %{
        "@context" => "https://schema.org",
        "@type" => "Blog",
        "name" => "Ordo blog",
        "url" => abs_url(index_path(locale)),
        "inLanguage" => locale,
        "publisher" => %{"@type" => "Organization", "name" => "Ordo", "url" => "https://hireordo.com"}
      },
      escape: :html_safe
    )
  end

  defp article_jsonld(post) do
    Jason.encode!(
      %{
        "@context" => "https://schema.org",
        "@type" => "BlogPosting",
        "headline" => post.title,
        "description" => post.description,
        "datePublished" => Date.to_iso8601(post.date),
        "inLanguage" => post.locale,
        "keywords" => Enum.join(post.tags, ", "),
        "mainEntityOfPage" => abs_url(post_path(post)),
        "author" => %{"@type" => "Organization", "name" => "Ordo"},
        "publisher" => %{"@type" => "Organization", "name" => "Ordo", "url" => "https://hireordo.com"}
      },
      escape: :html_safe
    )
  end

  ## RSS 2.0

  defp rss(locale, posts) do
    items = Enum.map_join(posts, "\n", &rss_item/1)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
      <channel>
        <title>Ordo blog</title>
        <link>#{abs_url(index_path(locale))}</link>
        <description>#{xml_escape(gettext("Practical notes on automating e-commerce customer support."))}</description>
        <language>#{locale}</language>
        <atom:link href="#{abs_url(feed_path(locale))}" rel="self" type="application/rss+xml"/>
    #{items}
      </channel>
    </rss>
    """
  end

  defp rss_item(post) do
    link = abs_url(post_path(post))

    """
        <item>
          <title>#{xml_escape(post.title)}</title>
          <link>#{link}</link>
          <guid isPermaLink="true">#{link}</guid>
          <pubDate>#{rfc822(post.date)}</pubDate>
          <description>#{xml_escape(post.description)}</description>
        </item>\
    """
  end

  defp rfc822(date) do
    days = ~w(Mon Tue Wed Thu Fri Sat Sun)
    months = ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
    dow = Enum.at(days, Date.day_of_week(date) - 1)
    mon = Enum.at(months, date.month - 1)
    "#{dow}, #{String.pad_leading(to_string(date.day), 2, "0")} #{mon} #{date.year} 00:00:00 +0000"
  end

  defp xml_escape(s) do
    s
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end
