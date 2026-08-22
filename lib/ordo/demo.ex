defmodule Ordo.Demo do
  @moduledoc """
  Fixture data for the One Day More demo tenant: shop identity, structured Policy
  facts (real rules from onedaymore.pl), seeded BaseLinker orders, and a ~24-email
  test mailbox including 4 deliberate edge cases. Pure data — orchestration
  (seed/reset/import) lives in `Ordo.Support`.
  """

  def slug, do: "onedaymore"

  def tenant_attrs do
    %{
      slug: slug(),
      name: "OneDayMore",
      support_email: "sklep@onedaymore.pl",
      signature: "Zespół OneDayMore",
      couriers: ["InPost", "DHL", "Orlen Paczka"]
    }
  end

  @doc "Structured, accepted Policy facts (see CONTEXT.md: Policy fact)."
  def policy_facts do
    [
      %{key: "return_window_days", label: "Okno zwrotu", value: "14", unit: "dni", category: "RETURN"},
      %{key: "return_conditions", label: "Warunki zwrotu",
        value: "produkt nieotwarty, oryginalne opakowanie, dowód zakupu + nr konta", category: "RETURN"},
      %{key: "refund_method", label: "Forma zwrotu środków",
        value: "ta sama, co przy zamówieniu, po otrzymaniu przesyłki", category: "RETURN_STATUS"},
      %{key: "complaint_resolution_days", label: "Rozpatrzenie reklamacji", value: "14", unit: "dni", category: "COMPLAINT"},
      %{key: "complaint_requirements", label: "Do reklamacji potrzebne",
        value: "nr zamówienia, nr partii, zdjęcia", category: "COMPLAINT"},
      %{key: "dispatch_time", label: "Czas wysyłki", value: "zwykle następny dzień roboczy", category: "PACKAGE_STATUS"},
      %{key: "free_shipping_standard", label: "Darmowa dostawa od", value: "149", unit: "zł", category: "PACKAGE_STATUS"},
      %{key: "free_shipping_club", label: "Darmowa dostawa (klub) od", value: "99", unit: "zł", category: "PACKAGE_STATUS"},
      %{key: "shipping_cost", label: "Koszt dostawy", value: "Orlen 8,99 zł, InPost/DHL 14,99 zł", category: "PACKAGE_STATUS"},
      %{key: "contact_email", label: "Kontakt", value: "sklep@onedaymore.pl", category: nil}
    ]
    |> Enum.with_index()
    |> Enum.map(fn {f, i} -> Map.put(f, :position, i) end)
  end

  # --- Orders (fake BaseLinker) ------------------------------------------

  @doc "Seeded orders as string-keyed maps (jsonb-friendly)."
  def orders, do: build_orders()

  @dispatched_history [
    %{"date" => "2026-08-20 08:40", "status" => "Nadano przesyłkę"},
    %{"date" => "2026-08-20 19:10", "status" => "Przyjęto w sortowni"},
    %{"date" => "2026-08-21 10:05", "status" => "Wydano do doręczenia"}
  ]
  @delivered_history @dispatched_history ++ [%{"date" => "2026-08-21 15:22", "status" => "Doręczono"}]

  defp order(num, date, status, sem, name, email, courier, tracking, history, items) do
    %{
      "number" => num, "date" => date, "status" => status, "semantic_status" => sem,
      "customer_name" => name, "customer_email" => email,
      "courier" => courier, "tracking" => tracking,
      "courier_history" => history, "items" => items
    }
  end

  defp build_orders do
    [
    order("ZAM-50101", "2026-08-14", "Wysłane", "dispatched", "Anna Kowalska", "anna.kowalska@gmail.com",
      "InPost", "620441882", @dispatched_history, [%{"name" => "Granola Belgijska Czekolada 450g", "qty" => 2}]),
    order("ZAM-50102", "2026-08-13", "Dostarczone", "delivered", "Marek Zieliński", "m.zielinski@wp.pl",
      "DHL", "JD0002210455", @delivered_history, [%{"name" => "Mix Keto Matcha 600g", "qty" => 1}]),
    order("ZAM-50103", "2026-08-18", "W realizacji", "processing", "Katarzyna Nowak", "k.nowak@onet.pl",
      nil, nil, [], [%{"name" => "Musli Proteinowe 400g", "qty" => 3}]),
    order("ZAM-50104", "2026-08-12", "Wysłane", "dispatched", "Piotr Wiśniewski", "piotrwis@gmail.com",
      "Orlen Paczka", "OP778812345", @dispatched_history, [%{"name" => "Owsianka Vegan Kakao 300g", "qty" => 4}]),
    order("ZAM-50105", "2026-08-19", "Nowe", "new", "Magdalena Lewandowska", "magda.lew@interia.pl",
      nil, nil, [], [%{"name" => "Granola Dubai Style 450g", "qty" => 1}]),
    order("ZAM-50106", "2026-08-11", "Dostarczone", "delivered", "Tomasz Kaczmarek", "t.kaczmarek@gmail.com",
      "InPost", "620559001", @delivered_history, [%{"name" => "Masło orzechowe 500g", "qty" => 2}]),
    order("ZAM-50107", "2026-08-17", "Wysłane", "dispatched", "Agnieszka Wójcik", "a.wojcik@gmail.com",
      "InPost", "620573114", @dispatched_history, [%{"name" => "Musli bez cukru Owoce Leśne 750g", "qty" => 1}]),
    order("ZAM-50108", "2026-08-16", "Spakowane", "processing", "Krzysztof Mazur", "kmazur@op.pl",
      nil, nil, [], [%{"name" => "Granola Proteinowa Wanilia 450g", "qty" => 2}]),
    order("ZAM-50109", "2026-08-10", "Dostarczone", "delivered", "Barbara Krawczyk", "b.krawczyk@wp.pl",
      "DHL", "JD0002211987", @delivered_history, [%{"name" => "Owsianka PreWorkout 400g", "qty" => 3}]),
    order("ZAM-50110", "2026-08-15", "Wysłane", "dispatched", "Michał Grabowski", "m.grabowski@gmail.com",
      "Orlen Paczka", "OP778890012", @dispatched_history, [%{"name" => "Mix Keto Kokos 600g", "qty" => 1}]),
    order("ZAM-50111", "2026-08-09", "Dostarczone", "delivered", "Ewa Pawlak", "ewa.pawlak@onet.pl",
      "InPost", "620601447", @delivered_history, [%{"name" => "Granola Dessert Sernikowa 400g", "qty" => 2}]),
    order("ZAM-50112", "2026-08-18", "W realizacji", "processing", "Robert Dąbrowski", "r.dabrowski@gmail.com",
      nil, nil, [], [%{"name" => "Musli dla dzieci 500g", "qty" => 5}]),
    order("ZAM-50113", "2026-08-14", "Wysłane", "dispatched", "Joanna Zając", "j.zajac@interia.pl",
      "DHL", "JD0002214003", @dispatched_history, [%{"name" => "Granola Belgijska Czekolada 450g", "qty" => 1}]),
    order("ZAM-50114", "2026-08-08", "Dostarczone", "delivered", "Paweł Król", "pawel.krol@gmail.com",
      "InPost", "620622889", @delivered_history, [%{"name" => "Musli Proteinowe 400g", "qty" => 2}]),
    order("ZAM-50115", "2026-08-16", "Wysłane", "dispatched", "Aleksandra Wieczorek", "ola.wieczorek@wp.pl",
      "Orlen Paczka", "OP778901234", @dispatched_history, [%{"name" => "Mix Keto Matcha 600g", "qty" => 1}]),
    # Edge case: same customer, TWO orders (ambiguous focus)
    order("ZAM-50116", "2026-08-05", "Dostarczone", "delivered", "Natalia Sikora", "n.sikora@gmail.com",
      "InPost", "620640001", @delivered_history, [%{"name" => "Granola Dubai Style 450g", "qty" => 1}]),
    order("ZAM-50130", "2026-08-19", "Wysłane", "dispatched", "Natalia Sikora", "n.sikora@gmail.com",
      "InPost", "620655777", @dispatched_history, [%{"name" => "Owsianka Vegan Kakao 300g", "qty" => 2}]),
    # English customer (international)
    order("ZAM-50117", "2026-08-13", "Wysłane", "dispatched", "James Miller", "james.miller@outlook.com",
      "DHL", "JD0009911223", @dispatched_history, [%{"name" => "Protein Granola Vanilla 450g", "qty" => 2}])
    ]
  end

  # --- Test mailbox (~24 emails) -----------------------------------------

  @doc "Predefined inbound emails for the demo tenant."
  def emails, do: build_emails()

  defp mail(name, email, subject, body), do: %{customer_name: name, customer_email: email, subject: subject, body: body}

  defp build_emails do
    [
    # PACKAGE_STATUS (status-heavy)
    mail("Anna Kowalska", "anna.kowalska@gmail.com", "Gdzie moja paczka?",
      "Dzień dobry, zamówiłam tydzień temu i wciąż nic nie dotarło. Gdzie jest moja przesyłka? Pozdrawiam, Anna"),
    mail("Piotr Wiśniewski", "piotrwis@gmail.com", "Śledzenie przesyłki ZAM-50104",
      "Witam, czy mogę prosić o numer do śledzenia zamówienia ZAM-50104? Chciałbym wiedzieć kiedy dotrze."),
    mail("Agnieszka Wójcik", "a.wojcik@gmail.com", "Kiedy dostawa?",
      "Dzień dobry, kiedy mniej więcej dostanę moje musli? Zamawiałam wczoraj."),
    mail("Michał Grabowski", "m.grabowski@gmail.com", "Nie ma paczki w paczkomacie",
      "Miałem odebrać paczkę Orlen, a nie dostałem kodu. Co dalej?"),
    mail("Joanna Zając", "j.zajac@interia.pl", "Status zamówienia",
      "Proszę o informację co się dzieje z moim zamówieniem, dawno je złożyłam."),
    mail("Katarzyna Nowak", "k.nowak@onet.pl", "Kiedy wyślecie ZAM-50103?",
      "Dzień dobry, zamówienie ZAM-50103 wciąż jest w realizacji. Kiedy zostanie wysłane?"),
    mail("Magdalena Lewandowska", "magda.lew@interia.pl", "gdzie paczka",
      "czemu tak długo, gdzie moja granola?"),
    mail("Aleksandra Wieczorek", "ola.wieczorek@wp.pl", "Przesyłka",
      "Dzień dobry, chciałabym dopytać o status mojej przesyłki. Dziękuję."),
    mail("Michał Grabowski", "m.grabowski@gmail.com", "Ile kosztuje dostawa?",
      "Ile płacę za wysyłkę i od jakiej kwoty jest darmowa?"),

    # RETURN
    mail("Tomasz Kaczmarek", "t.kaczmarek@gmail.com", "Chcę zwrócić masło orzechowe",
      "Witam, zamówiłem masło orzechowe (ZAM-50106) ale jednak chciałbym je zwrócić. Jak to zrobić?"),
    mail("Ewa Pawlak", "ewa.pawlak@onet.pl", "Zwrot produktu",
      "Dzień dobry, czy mogę zwrócić nieotwartą granolę? Ile mam na to czasu?"),

    # RETURN_STATUS
    mail("Barbara Krawczyk", "b.krawczyk@wp.pl", "Kiedy zwrot pieniędzy?",
      "Odesłałam produkty tydzień temu, kiedy dostanę zwrot środków za ZAM-50109?"),

    # INVOICE
    mail("Paweł Król", "pawel.krol@gmail.com", "Prośba o fakturę",
      "Dzień dobry, proszę o fakturę do zamówienia ZAM-50114."),
    mail("Robert Dąbrowski", "r.dabrowski@gmail.com", "Faktura na firmę",
      "Potrzebuję faktury na firmę do ZAM-50112. Dane wyślę w odpowiedzi."),

    # ORDER_CHANGE
    mail("Katarzyna Nowak", "k.nowak@onet.pl", "Zły adres dostawy",
      "Dzień dobry, podałam błędny adres w ZAM-50103. Czy da się jeszcze zmienić na: ul. Kwiatowa 5, Poznań?"),
    mail("Krzysztof Mazur", "kmazur@op.pl", "Dodać produkt do zamówienia",
      "Czy mogę dorzucić jeszcze jedno musli do zamówienia ZAM-50108 zanim wyślecie?"),

    # CANCELLATION
    mail("Robert Dąbrowski", "r.dabrowski@gmail.com", "Anulujcie zamówienie",
      "Proszę o anulowanie zamówienia ZAM-50112, rozmyśliłem się."),

    # COMPLAINT
    mail("Tomasz Kaczmarek", "t.kaczmarek@gmail.com", "Reklamacja - uszkodzone opakowanie",
      "Paczka przyszła zgnieciona a masło orzechowe rozbite w środku. Zamówienie ZAM-50106."),
    mail("Ewa Pawlak", "ewa.pawlak@onet.pl", "Krótka data ważności",
      "Dostałam granolę z datą ważności za 2 tygodnie, to chyba pomyłka?"),

    # OTHER
    mail("Zofia Adamczyk", "zofia.a@gmail.com", "Pytanie o skład",
      "Dzień dobry, czy granola Dubai Style jest wegańska? Nie chodzi o zamówienie, dopytuję przed zakupem."),
    mail("Grzegorz Bąk", "g.bak@wp.pl", "Godziny pracy sklepu",
      "W jakich godzinach mogę do Was zadzwonić?"),

    # --- 4 deliberate edge cases ---
    # (1) no matching order
    mail("Łukasz Nowicki", "lukasz.nowicki88@gmail.com", "Gdzie moje zamówienie?",
      "Zamawiałem kilka dni temu i nic nie przyszło. Nie pamiętam numeru zamówienia."),
    # (2) angry complaint
    mail("Halina Wróbel", "h.wrobel@onet.pl", "SKANDAL, spleśniałe musli!!!",
      "To jest żenada! Musli było SPLEŚNIAŁE, dzieci się rozchorowały. Żądam natychmiastowej reakcji!!!"),
    # (3) ambiguous — customer with two orders
    mail("Natalia Sikora", "n.sikora@gmail.com", "Gdzie paczka?",
      "Dzień dobry, gdzie jest moja paczka? Robiłam u Was ostatnio kilka zamówień."),
    # (4) English
    mail("James Miller", "james.miller@outlook.com", "Where is my order?",
      "Hello, I ordered a few days ago and I'd like to know when my granola will be delivered. Thanks, James")
    ]
  end
end
