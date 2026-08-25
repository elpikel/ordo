defmodule Ordo.Blog.Post do
  @moduledoc "Metadata for a single blog post in a single language."
  @enforce_keys [:slug, :locale, :ref, :title, :description, :date, :tags]
  defstruct [:slug, :locale, :ref, :title, :description, :date, :tags, read_minutes: 4]
end

defmodule Ordo.Blog do
  @moduledoc """
  Static, in-repo blog. Posts are plain data defined here — no database, no
  Markdown, no external dependency. Each post's metadata lives in `@posts`; its
  body is a HEEx function component in `OrdoWeb.BlogHTML` keyed by `{ref, locale}`.

  Bilingual: a post exists once per locale ("pl"/"en"), and the two language
  versions share a `ref` so we can cross-link them with `rel="alternate"`
  hreflang tags for SEO.
  """
  alias Ordo.Blog.Post

  @posts [
    %Post{
      ref: "support-automation",
      locale: "pl",
      slug: "jak-zautomatyzowac-obsluge-klienta-w-e-commerce",
      title: "Jak zautomatyzować obsługę klienta w e-commerce (bez utraty jakości)",
      description:
        "Praktyczny przewodnik: które maile obsługi da się zautomatyzować, jak zacząć od trybu Copilot i kiedy bezpiecznie przejść na Autopilota.",
      date: ~D[2026-02-10],
      tags: ["obsługa klienta", "automatyzacja", "e-commerce"],
      read_minutes: 6
    },
    %Post{
      ref: "support-automation",
      locale: "en",
      slug: "how-to-automate-ecommerce-customer-support",
      title: "How to Automate E-commerce Customer Support (Without Losing Quality)",
      description:
        "A practical guide: which support emails you can safely automate, how to start in Copilot mode, and when to switch to Autopilot.",
      date: ~D[2026-02-10],
      tags: ["customer support", "automation", "e-commerce"],
      read_minutes: 6
    },
    %Post{
      ref: "where-is-my-order",
      locale: "pl",
      slug: "gdzie-jest-moja-paczka-jak-odpowiadac-automatycznie",
      title: "„Gdzie jest moja paczka?” — jak odpowiadać automatycznie i trafnie",
      description:
        "Najczęstsze pytanie w obsłudze sklepu. Pokazujemy, jak łączyć status z BaseLinkera z odpowiedzią do klienta w kilka sekund.",
      date: ~D[2026-02-24],
      tags: ["BaseLinker", "wysyłka", "obsługa klienta"],
      read_minutes: 5
    },
    %Post{
      ref: "where-is-my-order",
      locale: "en",
      slug: "where-is-my-order-how-to-reply-automatically",
      title: "\"Where Is My Order?\" — How to Reply Automatically and Accurately",
      description:
        "The single most common support question. Here's how to turn a BaseLinker tracking status into a customer-ready reply in seconds.",
      date: ~D[2026-02-24],
      tags: ["BaseLinker", "shipping", "customer support"],
      read_minutes: 5
    }
  ]

  @doc "All posts for a locale, newest first."
  def list(locale) do
    @posts
    |> Enum.filter(&(&1.locale == locale))
    |> Enum.sort_by(& &1.date, {:desc, Date})
  end

  @doc "A single post by locale + slug, or nil."
  def get(locale, slug), do: Enum.find(@posts, &(&1.locale == locale and &1.slug == slug))

  @doc "The same post in another locale (matched by `ref`), or nil."
  def translation(%Post{ref: ref}, locale), do: Enum.find(@posts, &(&1.ref == ref and &1.locale == locale))

  @doc "Every post across all locales — used by the sitemap."
  def all, do: @posts

  @doc "Supported blog locales."
  def locales, do: ~w(pl en)
end
