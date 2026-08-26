defmodule OrdoWeb.BlogHTML do
  @moduledoc """
  Static blog rendering — a self-contained SEO layout plus one HEEx body per
  post, keyed by `{ref, locale}`. No Markdown, no runtime transformation: the
  article content IS HEEx.
  """
  use OrdoWeb, :html

  ## Pages

  def index(assigns) do
    ~H"""
    <.layout
      title={@page_title}
      description={@description}
      canonical={@canonical}
      alternates={@alternates}
      locale={@locale}
      jsonld={@jsonld}
      feed_url={@feed_url}
    >
      <div class="max-w-3xl mx-auto px-5 sm:px-8 py-14">
        <p class="font-mono text-xs tracking-[0.25em] text-ink-mute uppercase mb-3">
          {gettext("Blog")}
        </p>
        <h1 class="font-display font-bold text-4xl tracking-tight mb-3">
          {gettext("Ordo blog")}
        </h1>
        <p class="text-lg text-ink-soft mb-12 max-w-xl">
          {gettext("Practical notes on automating e-commerce customer support.")}
        </p>

        <ul class="space-y-10">
          <li :for={post <- @posts} class="border-b border-slate-200 pb-10 last:border-0">
            <p class="font-mono text-xs text-ink-mute mb-2">
              <time datetime={Date.to_iso8601(post.date)}>{format_date(post.date, post.locale)}</time>
              · {post.read_minutes} {gettext("min read")}
            </p>
            <h2 class="font-display font-bold text-2xl tracking-tight leading-snug mb-2">
              <.link navigate={post_path(post)} class="hover:text-label-deep transition-colors">
                {post.title}
              </.link>
            </h2>
            <p class="text-ink-soft leading-relaxed mb-3">{post.description}</p>
            <div class="flex flex-wrap gap-2">
              <span
                :for={tag <- post.tags}
                class="font-mono text-[11px] text-ink-mute border border-slate-200 px-2 py-0.5"
              >
                {tag}
              </span>
            </div>
          </li>
        </ul>
      </div>
    </.layout>
    """
  end

  def show(assigns) do
    ~H"""
    <.layout
      title={@post.title}
      description={@post.description}
      canonical={@canonical}
      alternates={@alternates}
      locale={@post.locale}
      jsonld={@jsonld}
      feed_url={@feed_url}
    >
      <article class="max-w-2xl mx-auto px-5 sm:px-8 py-14">
        <.link
          navigate={index_path(@post.locale)}
          class="font-mono text-xs text-ink-mute hover:text-ink"
        >
          ← {gettext("Blog")}
        </.link>

        <header class="mt-6 mb-8">
          <p class="font-mono text-xs text-ink-mute mb-3">
            <time datetime={Date.to_iso8601(@post.date)}>
              {format_date(@post.date, @post.locale)}
            </time>
            · {@post.read_minutes} {gettext("min read")}
          </p>
          <h1 class="font-display font-bold text-3xl sm:text-4xl tracking-tight leading-[1.12]">
            {@post.title}
          </h1>
        </header>

        <div class="blog-prose">
          <.article ref={@post.ref} locale={@post.locale} />
        </div>

        <aside class="mt-14 border-t-2 border-ink pt-8">
          <p class="font-display font-bold text-xl mb-2">{gettext("See Ordo in action")}</p>
          <p class="text-ink-soft mb-4">
            {gettext(
              "Ordo reads your support inbox, acts in BaseLinker, and drafts the reply. Watch it work on a live demo."
            )}
          </p>
          <a
            href={~p"/demo"}
            class="inline-block bg-ink text-paper font-mono text-sm px-6 py-3 hover:bg-ink-soft transition-colors"
          >
            {gettext("See live demo")} →
          </a>
        </aside>
      </article>
    </.layout>
    """
  end

  ## SEO layout shell (full HTML document, rendered without the root layout)

  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :canonical, :string, required: true
  attr :alternates, :list, required: true, doc: "list of %{locale, href, current?}"
  attr :locale, :string, required: true
  attr :jsonld, :string, required: true, doc: "raw JSON-LD script body"
  attr :feed_url, :string, required: true
  slot :inner_block, required: true

  def layout(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang={@locale}>
      <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <title>{@title} · Ordo</title>
        <meta name="description" content={@description} />
        <link rel="canonical" href={@canonical} />
        <link
          :for={alt <- @alternates}
          rel="alternate"
          hreflang={alt.locale}
          href={alt.href}
        />
        <link rel="alternate" hreflang="x-default" href={x_default(@alternates)} />
        <meta property="og:type" content="article" />
        <meta property="og:title" content={@title} />
        <meta property="og:description" content={@description} />
        <meta property="og:url" content={@canonical} />
        <meta property="og:site_name" content="Ordo" />
        <meta name="twitter:card" content="summary" />
        <link rel="alternate" type="application/rss+xml" title="Ordo blog" href={@feed_url} />
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
        <link
          href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@500;700&family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Mono:wght@400;500&display=swap"
          rel="stylesheet"
        />
        <link rel="icon" href={~p"/favicon.svg"} type="image/svg+xml" />
        <link phx-track-static rel="stylesheet" href={~p"/assets/css/app.css"} />
        {Phoenix.HTML.raw(~s(<script type="application/ld+json">) <> @jsonld <> "</script>")}
      </head>
      <body class="bg-paper text-ink font-body antialiased">
        <header class="max-w-3xl mx-auto px-5 sm:px-8 pt-6 flex items-center justify-between">
          <a href={~p"/"} class="font-mono font-medium tracking-[0.35em] text-lg select-none">
            ORDO<span class="text-label-deep">.</span>
          </a>
          <nav class="flex items-center gap-4 font-mono text-xs">
            <a
              :for={alt <- @alternates}
              href={alt.href}
              class={[
                "uppercase px-1 py-0.5",
                (alt.current? && "text-ink font-semibold") || "text-ink-mute hover:text-ink"
              ]}
            >
              {alt.locale}
            </a>
          </nav>
        </header>

        {render_slot(@inner_block)}

        <footer class="max-w-3xl mx-auto px-5 sm:px-8 py-12 mt-8 border-t border-slate-200 font-mono text-xs text-ink-mute flex flex-wrap gap-4 justify-between">
          <span>© Ordo · <a href="https://hireordo.com" class="hover:text-ink">hireordo.com</a></span>
          <a href={~p"/"} class="hover:text-ink">{gettext("Back to homepage")}</a>
        </footer>
      </body>
    </html>
    """
  end

  ## Helpers

  def post_path(%{locale: "en", slug: slug}), do: ~p"/en/blog/#{slug}"
  def post_path(%{slug: slug}), do: ~p"/blog/#{slug}"

  def index_path("en"), do: ~p"/en/blog"
  def index_path(_), do: ~p"/blog"

  defp x_default(alternates) do
    default = Enum.find(alternates, &(&1.locale == "pl")) || List.first(alternates)
    default.href
  end

  defp format_date(date, "en"), do: Calendar.strftime(date, "%B %-d, %Y")

  defp format_date(date, _) do
    months =
      ~w(stycznia lutego marca kwietnia maja czerwca lipca sierpnia września października listopada grudnia)

    "#{date.day} #{Enum.at(months, date.month - 1)} #{date.year}"
  end

  ## Article bodies — pure HEEx, one clause per {ref, locale}

  attr :ref, :string, required: true
  attr :locale, :string, required: true

  def article(%{ref: "support-automation", locale: "pl"} = assigns) do
    ~H"""
    <p>
      Obsługa klienta w e-commerce to w większości powtarzalne pytania: status paczki, zwrot,
      faktura, zmiana zamówienia. Dobra wiadomość jest taka, że właśnie ta powtarzalność sprawia,
      że można ją bezpiecznie zautomatyzować — o ile robisz to stopniowo i na danych, a nie na obietnicach.
    </p>

    <h2>Zacznij od kategoryzacji, nie od odpowiedzi</h2>
    <p>
      Zanim cokolwiek zautomatyzujesz, poznaj strukturę swojej skrzynki. Zwykle 5–7 kategorii
      pokrywa 80% ruchu. Kiedy wiesz, ile procent to „gdzie moja paczka", a ile to reklamacje,
      wiesz też, gdzie automatyzacja da największy zwrot.
    </p>

    <h2>Tryb Copilot: automat pisze, człowiek zatwierdza</h2>
    <p>
      Najbezpieczniejszy start to tryb, w którym system przygotowuje wersję roboczą odpowiedzi
      — opartą na realnych danych zamówienia — a Ty ją tylko zatwierdzasz. Zyskujesz czas,
      nie tracąc kontroli. Po kilku tygodniach widzisz, w których kategoriach wersje robocze
      przestają wymagać poprawek.
    </p>
    <ul>
      <li>Odpowiedzi grają z Twoimi zasadami sklepu (terminy, koszty, wyjątki).</li>
      <li>Każda odpowiedź jest oparta na zamówieniu, a nie na ogólnym szablonie.</li>
      <li>Masz metrykę: ile wersji roboczych trafia bez edycji.</li>
    </ul>

    <h2>Autopilot — po jednej kategorii, na podstawie liczb</h2>
    <p>
      Gdy w danej kategorii wersje robocze są trafne w 95%+, możesz przełączyć ją na pełną
      automatyzację. Kluczowe: robisz to <strong>kategoria po kategorii</strong>. Statusy paczek
      mogą działać samodzielnie, a reklamacje niech na zawsze wymagają akceptacji człowieka —
      jeśli tak śpisz spokojniej.
    </p>

    <h2>Podsumowanie</h2>
    <p>
      Automatyzacja obsługi nie oznacza „wyłączam ludzi". Oznacza: automat bierze na siebie
      nudne, powtarzalne 80%, a Twój zespół zajmuje się trudnymi 20%, gdzie naprawdę jest potrzebny.
    </p>
    """
  end

  def article(%{ref: "support-automation", locale: "en"} = assigns) do
    ~H"""
    <p>
      E-commerce customer support is mostly repetitive questions: parcel status, returns, invoices,
      order changes. The good news is that this repetitiveness is exactly what makes support safe to
      automate — as long as you do it gradually and based on data, not promises.
    </p>

    <h2>Start with categorization, not replies</h2>
    <p>
      Before automating anything, understand the shape of your inbox. Usually 5–7 categories cover
      80% of the volume. Once you know how much is "where is my order" versus complaints, you know
      where automation pays off most.
    </p>

    <h2>Copilot mode: the machine drafts, a human approves</h2>
    <p>
      The safest start is a mode where the system prepares a draft reply — grounded in real order
      data — and you simply approve it. You gain time without losing control. After a few weeks you
      can see which categories no longer need edits.
    </p>
    <ul>
      <li>Replies follow your shop rules (deadlines, costs, exceptions).</li>
      <li>Every reply is based on the actual order, not a generic template.</li>
      <li>You get a metric: how many drafts ship without edits.</li>
    </ul>

    <h2>Autopilot — one category at a time, based on numbers</h2>
    <p>
      When drafts in a category are 95%+ accurate, you can switch it to full automation. The key:
      you do it <strong>category by category</strong>. Parcel statuses can run on their own, while
      complaints can stay human-approved forever — if that's how you sleep better.
    </p>

    <h2>Takeaway</h2>
    <p>
      Automating support doesn't mean "removing people". It means the machine takes the boring,
      repetitive 80%, and your team handles the hard 20% where they're actually needed.
    </p>
    """
  end

  def article(%{ref: "where-is-my-order", locale: "pl"} = assigns) do
    ~H"""
    <p>
      „Gdzie jest moja paczka?" to najczęstsze pytanie w każdym sklepie internetowym. Samo w sobie
      jest proste, ale odpowiedź wymaga trzech rzeczy naraz: znalezienia zamówienia, sprawdzenia
      statusu przesyłki i napisania jasnej wiadomości do klienta.
    </p>

    <h2>Problem nie leży w treści, tylko w kontekście</h2>
    <p>
      Klient nie chce szablonu „sprawdzimy i wrócimy". Chce konkretu: gdzie jest paczka, u jakiego
      przewoźnika i kiedy dotrze. To dane, które masz już w BaseLinkerze — problem w tym, że
      wyciągnięcie ich ręcznie przy każdym mailu zabiera czas.
    </p>

    <h2>Trzy kroki, które da się zautomatyzować</h2>
    <ul>
      <li><strong>Dopasowanie zamówienia</strong> — po adresie e-mail lub numerze zamówienia.</li>
      <li><strong>Odczyt statusu</strong> — numer przesyłki, przewoźnik, etap doręczenia.</li>
      <li><strong>Odpowiedź</strong> — zwięzła, z linkiem do śledzenia i przewidywanym terminem.</li>
    </ul>

    <h2>Jak wygląda dobra odpowiedź</h2>
    <p>
      „Cześć Anna! Twoja paczka wyszła od nas 12 sierpnia i dziś jest w doręczeniu. Śledź ją tutaj:
      inpost.pl/620441882. Powinna dotrzeć do paczkomatu do godziny 18:00." Konkret, ton marki,
      zero ogólników — i wysłane w kilka sekund zamiast kilku minut.
    </p>

    <h2>Podsumowanie</h2>
    <p>
      Pytanie o paczkę to idealny kandydat na pierwszą automatyzację: wysoka objętość, niskie ryzyko,
      dane już masz. Zacznij tutaj, zmierz skuteczność, a potem rozszerzaj na kolejne kategorie.
    </p>
    """
  end

  def article(%{ref: "where-is-my-order", locale: "en"} = assigns) do
    ~H"""
    <p>
      "Where is my order?" is the most common question in any online store. The question is simple,
      but the answer needs three things at once: finding the order, checking the shipment status,
      and writing a clear message to the customer.
    </p>

    <h2>The problem isn't the wording — it's the context</h2>
    <p>
      Customers don't want a "we'll check and get back to you" template. They want specifics: where
      the parcel is, which carrier has it, and when it arrives. That data already lives in
      BaseLinker — the problem is that pulling it by hand for every email takes time.
    </p>

    <h2>Three steps you can automate</h2>
    <ul>
      <li><strong>Match the order</strong> — by email address or order number.</li>
      <li><strong>Read the status</strong> — tracking number, carrier, delivery stage.</li>
      <li><strong>Reply</strong> — concise, with a tracking link and an expected delivery time.</li>
    </ul>

    <h2>What a good reply looks like</h2>
    <p>
      "Hi Anna! Your parcel left us on 12 Aug and is out for delivery today. Track it here:
      inpost.pl/620441882. It should reach your locker by 6 pm." Specific, on-brand, no filler —
      and sent in seconds instead of minutes.
    </p>

    <h2>Takeaway</h2>
    <p>
      The parcel question is the perfect first automation: high volume, low risk, and you already
      have the data. Start here, measure accuracy, then expand to more categories.
    </p>
    """
  end
end
