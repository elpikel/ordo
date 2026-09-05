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
        <script defer data-domain="hireordo.com" data-api="/api/event" src="/js/stats.js">
        </script>
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

  def article(%{ref: "getting-started", locale: "pl"} = assigns) do
    ~H"""
    <p>
      Ordo to jedna skrzynka, w której lądują wiadomości od klientów — a przy każdej od razu czeka
      gotowa odpowiedź, oparta na danych Twojego sklepu. Uruchomienie zajmuje kilkanaście minut i nie
      wymaga zmiany niczego w sklepie. Oto jak zacząć.
    </p>

    <h2>Krok 1: Podłącz swój sklep</h2>
    <p>
      W ustawieniach wklej token API z BaseLinkera (panel BaseLinker → Moje konto → API). Dzięki temu
      Ordo odczyta zamówienie, status przesyłki i historię — czyli kontekst, na którym opiera każdą
      odpowiedź. Token jest zaszyfrowany i nigdy nie jest pokazywany ponownie.
    </p>

    <h2>Krok 2: Dodaj skrzynkę obsługi</h2>
    <p>
      Podłącz skrzynkę, na którą piszą klienci (IMAP — adres serwera, login, hasło). Ordo zaczyna
      czytać nowe wiadomości i zamieniać je w zgłoszenia. Nic nie znika z Twojej skrzynki — Ordo
      działa równolegle.
    </p>

    <h2>Krok 3 (opcjonalnie): Podłącz Google</h2>
    <p>
      Jeśli zbierasz opinie w Profilu Firmy w Google, połącz go jednym kliknięciem. Opinie trafiają do
      tej samej skrzynki co wiadomości, a Ordo przygotowuje na nie odpowiedzi — te negatywne zawsze
      czekają na akceptację człowieka.
    </p>

    <h2>Krok 4: Copilot pisze, Ty zatwierdzasz</h2>
    <p>
      Na start Ordo działa w trybie Copilot: przy każdym zgłoszeniu przygotowuje wersję roboczą
      odpowiedzi — dopasowaną do zamówienia i zasad Twojego sklepu. Czytasz, w razie potrzeby
      poprawiasz i zatwierdzasz. Zyskujesz czas, nie tracąc kontroli.
    </p>

    <h2>Krok 5: Zatwierdzaj skądkolwiek</h2>
    <p>
      Nie musisz siedzieć w panelu. Włącz powiadomienia w ustawieniach, a o każdej gotowej odpowiedzi
      dostaniesz maila z przyciskiem „Zatwierdź i wyślij" albo wiadomość na WhatsAppie, którą
      zatwierdzisz, odpisując „OK". Oryginalna wiadomość i proponowana odpowiedź są w powiadomieniu —
      decydujesz w kilka sekund.
    </p>

    <h2>Krok 6: Włącz Autopilota — po jednej kategorii</h2>
    <p>
      Gdy w danej kategorii wersje robocze są trafne (np. statusy paczek), przełącz ją na Autopilota —
      Ordo odpowiada samodzielnie. Reklamacje możesz na zawsze zostawić do akceptacji człowieka.
      Zmiany robisz <strong>kategoria po kategorii</strong>, na podstawie liczb, a nie na wiarę.
    </p>

    <h2>Podsumowanie</h2>
    <p>
      Zacznij od podłączenia sklepu i skrzynki, kilka dni popracuj w Copilocie, a potem przełączaj
      bezpieczne kategorie na Autopilota. Małe kroki, mierzalny efekt — i coraz spokojniejsza skrzynka.
    </p>
    """
  end

  def article(%{ref: "ordo-vs-chatbot", locale: "pl"} = assigns) do
    ~H"""
    <p>
      Sklep, który myśli o automatyzacji obsługi, zwykle najpierw myśli „chatbot". To rozsądny pierwszy
      krok — ale warto wiedzieć, czym różni się typowy chatbot AI od asystenta opartego na danych
      zamówień, takiego jak Ordo. Rozwiązują trochę inne problemy.
    </p>

    <h2>Chatbot odpowiada z bazy wiedzy. Ordo — z zamówienia.</h2>
    <p>
      Typowy chatbot odpowiada na podstawie FAQ i artykułów, którymi go nakarmisz. Poradzi sobie z
      „jaki macie czas dostawy?", ale przy „gdzie jest moje zamówienie?" utknie, bo nie zna konkretnej
      paczki. Ordo najpierw znajduje zamówienie (po adresie e-mail lub numerze), odczytuje status
      przesyłki i dopiero na tej podstawie pisze odpowiedź. To różnica między ogólnikiem a konkretem.
    </p>

    <h2>Rozmowa kontra działanie</h2>
    <p>
      Chatbot prowadzi rozmowę. Ordo wykonuje pracę: sprawdza tracking, rejestruje zwrot, uruchamia
      zwrot środków — realne akcje w Twoim sklepie, a nie tylko tekst. Klient dostaje rozwiązanie, a nie
      obietnicę „przekażemy dalej".
    </p>

    <h2>Wszystko albo nic kontra stopniowe zaufanie</h2>
    <p>
      Chatbota zwykle albo włączasz na całość, albo wcale. Ordo działa inaczej: zaczyna w trybie
      Copilot (pisze wersję roboczą, Ty zatwierdzasz), a pełną automatykę włączasz <strong>kategoria po kategorii</strong>, gdy liczby to potwierdzą. Statusy paczek mogą działać
      same, a reklamacje zostają pod okiem człowieka. Automatyzujesz tyle, ile jest bezpieczne.
    </p>

    <h2>Widget na stronie kontra jedna skrzynka</h2>
    <p>
      Chatbot mieszka najczęściej w okienku na stronie. Ordo zbiera to, co i tak już przychodzi —
      wiadomości i opinie w Profilu Firmy w Google — do jednej skrzynki i odsyła odpowiedzi tym samym
      kanałem. Nie zmuszasz klienta do nowego kanału; wchodzisz tam, gdzie już pisze.
    </p>

    <h2>Kiedy chatbot ma sens</h2>
    <p>
      Uczciwie: chatbot bywa świetny przed zakupem — natychmiastowa odpowiedź na proste pytania na
      stronie, zanim zamienią się w wiadomość do obsługi. Jeśli tego szukasz, dobry widget zrobi robotę.
    </p>

    <h2>Podsumowanie</h2>
    <p>
      Chatbot i Ordo to nie to samo narzędzie do tego samego zadania. Do FAQ na stronie — chatbot. Do
      obsługi po zakupie, opartej na realnych zamówieniach i konkretnych akcjach — asystent taki jak
      Ordo, który zaczyna ostrożnie i zdobywa zaufanie liczbami. Wiele sklepów używa obu.
    </p>
    """
  end

  def article(%{ref: "ordo-vs-chatbot", locale: "en"} = assigns) do
    ~H"""
    <p>
      A shop thinking about support automation usually thinks "chatbot" first. That's a reasonable
      start — but it's worth knowing how a generic AI chatbot differs from an order-grounded assistant
      like Ordo. They solve slightly different problems.
    </p>

    <h2>A chatbot answers from a knowledge base. Ordo answers from the order.</h2>
    <p>
      A typical chatbot replies from the FAQ and articles you feed it. It can handle "what's your
      delivery time?", but "where is my order?" stops it — it doesn't know the specific parcel. Ordo
      first finds the order (by email address or number), reads the shipment status, and only then
      writes the reply. That's the difference between a generality and a specific.
    </p>

    <h2>Conversation vs action</h2>
    <p>
      A chatbot holds a conversation. Ordo does the work: checks tracking, registers the return,
      triggers the refund — real actions in your shop, not just text. The customer gets a resolution,
      not a "we'll pass it on".
    </p>

    <h2>All-or-nothing vs earned trust</h2>
    <p>
      A chatbot is usually on or off. Ordo works differently: it starts in Copilot mode (drafts a
      reply, you approve), and you switch full automation on <strong>category by category</strong>
      once
      the numbers back it up. Parcel statuses can run on their own; complaints stay human-approved. You
      automate exactly as much as is safe.
    </p>

    <h2>A website widget vs one inbox</h2>
    <p>
      A chatbot usually lives in a widget on your site. Ordo gathers what already comes in — messages
      and Google Business Profile reviews — into one inbox, and sends replies back on the same channel.
      You don't force customers onto a new channel; you meet them where they already write.
    </p>

    <h2>When a chatbot makes sense</h2>
    <p>
      To be fair: a chatbot can be great pre-purchase — instant answers to simple questions on the
      page, deflecting easy queries before they become support messages. If that's what you need, a
      good widget does the job.
    </p>

    <h2>Takeaway</h2>
    <p>
      A chatbot and Ordo aren't the same tool for the same job. For on-site FAQ, a chatbot. For
      post-purchase support grounded in real orders and concrete actions, an assistant like Ordo — one
      that starts cautiously and earns trust with numbers. Plenty of shops use both.
    </p>
    """
  end

  def article(%{ref: "getting-started", locale: "en"} = assigns) do
    ~H"""
    <p>
      Ordo is one inbox where customer messages land — each already paired with a ready-to-send reply
      grounded in your shop's data. Setup takes about fifteen minutes and changes nothing in your
      store. Here's how to get started.
    </p>

    <h2>Step 1: Connect your shop</h2>
    <p>
      In settings, paste your BaseLinker API token (BaseLinker panel → My account → API). This lets
      Ordo read the order, shipment status, and history — the context behind every reply. The token is
      encrypted and never shown again.
    </p>

    <h2>Step 2: Add your support mailbox</h2>
    <p>
      Connect the mailbox your customers write to (IMAP — server, username, password). Ordo starts
      reading new messages and turning them into tickets. Nothing disappears from your mailbox — Ordo
      runs alongside it.
    </p>

    <h2>Step 3 (optional): Connect Google</h2>
    <p>
      If you collect reviews on your Google Business Profile, connect it in one click. Reviews land in
      the same inbox as your messages, and Ordo drafts replies for them — negative ones always wait
      for a human to approve.
    </p>

    <h2>Step 4: Copilot drafts, you approve</h2>
    <p>
      Ordo starts in Copilot mode: for every ticket it prepares a draft reply — matched to the order
      and your shop rules. You read it, tweak if needed, and approve. You gain time without giving up
      control.
    </p>

    <h2>Step 5: Approve from anywhere</h2>
    <p>
      You don't have to sit in the dashboard. Turn on notifications in settings and every ready reply
      arrives as an email with an "Approve and send" button, or a WhatsApp message you approve by
      replying "OK". The original message and the proposed reply are right there — you decide in
      seconds.
    </p>

    <h2>Step 6: Switch on Autopilot — one category at a time</h2>
    <p>
      When drafts in a category are consistently accurate (say, parcel statuses), switch it to
      Autopilot and Ordo replies on its own. Complaints can stay human-approved forever. You make the
      change <strong>category by category</strong>, based on numbers, not faith.
    </p>

    <h2>Takeaway</h2>
    <p>
      Connect your shop and mailbox, spend a few days in Copilot, then move the safe categories to
      Autopilot. Small steps, measurable results — and a calmer inbox every week.
    </p>
    """
  end
end
