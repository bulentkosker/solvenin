// ============================================================
// i18n/pl.js — Solvenin PL translations
// Auto-extracted from legacy i18n.js. Loaded on demand by loader.js.
// ============================================================
window.T = window.T || {};
window.T.pl = {
    // === POLISH FULL BLOCK (user-spec keys; rest fall back to en at runtime) ===
    nav_dashboard:'Panel główny',
    nav_inventory:'Magazyn',
    nav_sales:'Sprzedaż',
    nav_purchasing:'Zakupy',
    nav_contacts:'Kontakty',
    nav_finance:'Finanse',
    nav_accounting:'Księgowość',
    nav_hr:'Kadry',
    nav_production:'Produkcja',
    nav_projects:'Projekty',
    nav_shipping:'Wysyłka',
    nav_maintenance:'Konserwacja',
    nav_crm:'CRM',
    nav_reports:'Raporty',
    nav_settings:'Ustawienia',
    nav_pos:'POS',
    nav_subscription:'Subskrypcja',
    btn_save:'Zapisz',
    btn_cancel:'Anuluj',
    btn_delete:'Usuń',
    btn_edit:'Edytuj',
    btn_add:'Dodaj',
    btn_new:'Nowy',
    btn_search:'Szukaj',
    btn_filter:'Filtruj',
    btn_export:'Eksportuj',
    btn_import:'Importuj',
    btn_print:'Drukuj',
    btn_download:'Pobierz',
    btn_confirm:'Potwierdź',
    btn_back:'Wstecz',
    btn_close:'Zamknij',
    btn_view:'Wyświetl',
    btn_refresh:'Odśwież',
    label_name:'Nazwa',
    label_email:'E-mail',
    label_phone:'Telefon',
    label_address:'Adres',
    label_date:'Data',
    label_amount:'Kwota',
    label_total:'Łącznie',
    label_subtotal:'Suma częściowa',
    label_tax:'VAT',
    label_discount:'Zniżka',
    label_notes:'Notatki',
    label_status:'Status',
    label_description:'Opis',
    label_quantity:'Ilość',
    label_unit:'Jednostka',
    label_price:'Cena',
    label_currency:'Waluta',
    label_country:'Kraj',
    label_city:'Miasto',
    label_company:'Firma',
    label_customer:'Klient',
    label_supplier:'Dostawca',
    label_order_number:'Numer zamówienia',
    label_invoice_number:'Numer faktury',
    label_due_date:'Termin płatności',
    label_payment_method:'Metoda płatności',
    label_cash:'Gotówka',
    label_bank_transfer:'Przelew bankowy',
    label_credit_card:'Karta kredytowa',
    status_draft:'Szkic',
    status_confirmed:'Potwierdzony',
    status_invoiced:'Zafakturowany',
    status_paid:'Opłacony',
    status_overdue:'Przeterminowany',
    status_cancelled:'Anulowany',
    status_active:'Aktywny',
    status_inactive:'Nieaktywny',
    toast_saved:'Zapisano pomyślnie',
    toast_deleted:'Usunięto pomyślnie',
    toast_error:'Wystąpił błąd',
    toast_loading:'Ładowanie...',
    toast_no_data:'Nie znaleziono danych',
    toast_confirm_delete:'Czy na pewno chcesz usunąć?',
    label_invoice:'Faktura',
    label_order:'Zamówienie',
    label_warehouse:'Magazyn',
    label_product:'Produkt',
    label_category:'Kategoria',
    label_stock_movement:'Ruch magazynowy',
    label_cash_register:'Kasa',
    label_bank_account:'Konto bankowe',
    label_journal_entry:'Zapis księgowy',
    label_chart_of_accounts:'Plan kont',
    label_trial_balance:'Bilans próbny',
    label_balance_sheet:'Bilans',
    label_income_statement:'Rachunek zysków i strat',
    label_employee:'Pracownik',
    label_department:'Dział',
    label_opportunity:'Szansa',
    label_pipeline:'Pipeline',
    placeholder_search:'Szukaj...',
    placeholder_enter_name:'Wprowadź nazwę...',
    placeholder_select:'Wybierz...',
    placeholder_optional:'Opcjonalne...',
    placeholder_enter_amount:'Wprowadź kwotę...',
    lbl_tax_rate:'Stawka podatku',
    col_unit_price:'Cena jednostkowa',
    lbl_total:'Łącznie',
    // === POS PAGE ===
    pos_cart:'Koszyk',
    pos_complete_payment:'Zakończ płatność',
    pos_change:'Reszta',
    pos_received_amount:'Kwota otrzymana',
    pos_exact_payment:'Dokładnie',
    pos_clear_cart:'Wyczyść',
    pos_select_register:'Wybierz kasę',
    pos_start_session:'Rozpocznij',
    pos_manager_pin:'Potwierdzenie menedżera',
    pos_guest:'Gość',
    pos_select_customer:'Wybierz klienta',
    pos_cash:'Gotówka',
    pos_card:'Karta',
    pos_transfer:'Przelew',
    pos_cash_payment:'Płatność gotówką',
    pos_card_payment:'Płatność kartą',
    pos_total:'Łącznie',
    pos_subtotal:'Suma częściowa',
    pos_tax:'VAT',
    pos_account:'Konto',
    pos_select_account:'Wybierz konto...',
    pos_sale_completed:'Sprzedaż zakończona',
    pos_new_sale:'Nowa sprzedaż',
    pos_change_label:'Reszta',
    pos_exit:'Wyjdź',
    pos_register_label:'Na której kasie będziesz pracować?',
    pos_barcode_placeholder:'📦 Zeskanuj lub wpisz kod kreskowy...',
    pos_scan_to_add:'Zeskanuj, aby dodać produkt',
    pos_no_quick_buttons:'Brak przycisków szybkiego dostępu',
    pos_all_categories:'Wszystkie',
    pos_qty_decrease_pin:'Zmniejszenie ilości wymaga zatwierdzenia menedżera',
    pos_remove_item_pin:'Usunięcie produktu wymaga zatwierdzenia menedżera',
    pos_edit_qty_pin:'Zmiana ilości wymaga zatwierdzenia menedżera',
    pos_clear_cart_pin:'Wprowadź PIN menedżera, aby wyczyścić koszyk',
    pos_cancel_receipt_pin:'Wprowadź PIN menedżera, aby anulować paragon',
    pos_toast_no_register:'Brak zdefiniowanej kasy. Dodaj w Ustawienia > Kasa i Bank.',
    pos_toast_session_failed:'Nie udało się otworzyć sesji',
    pos_toast_barcode_not_found:'Nie znaleziono kodu kreskowego',
    pos_toast_cart_restored:'Przywrócono poprzedni paragon',
    pos_toast_cart_cleared:'Koszyk wyczyszczony',
    pos_toast_manager_session_ended:'Sesja menedżera zakończona',
    pos_toast_wrong_pin:'Niepoprawny PIN',
    pos_toast_insufficient:'Niewystarczająca kwota',
    pos_toast_select_account:'Wybierz konto',
    pos_toast_error_prefix:'Błąd',
    pos_toast_cart_not_empty:'Koszyk zawiera produkty — najpierw zakończ lub anuluj paragon',
    pos_clear:'Wyczyść',
    // === TRACKING / VARIANTS / SERIALS / LOTS ===
    section_tracking:'Śledzenie i warianty',
    label_tracking_type:'Typ śledzenia',
    track_none:'Brak śledzenia',
    track_variant:'Warianty',
    track_serial:'Numery seryjne',
    track_lot:'Partia',
    label_attributes:'Atrybuty',
    btn_add_attribute:'Dodaj atrybut',
    label_variants:'Warianty',
    btn_regen_variants:'Wygeneruj',
    label_serial_numbers:'Numery seryjne',
    btn_add_serial:'Dodaj',
    btn_add_serial_range:'Zakres',
    label_lots:'Partie',
    btn_add_lot:'Dodaj partię',
    inv_no_attrs:'Brak atrybutów',
    inv_no_variants:'Najpierw dodaj atrybuty, potem kliknij Wygeneruj',
    inv_no_serials:'Brak numerów seryjnych',
    inv_no_lots:'Brak partii',
    label_serial:'Nr seryjny',
    label_warranty:'Gwarancja',
    label_lot_number:'Nr partii',
    label_expiry:'Data ważności',
    label_days_left:'Pozostałe dni',
    label_value:'Wartość',
    label_variant:'Wariant',
    label_barcode:'Kod kreskowy',
    label_stock:'Zapas',
    label_price_extra:'+Cena',
    sn_in_stock:'W magazynie',
    sn_sold:'Sprzedany',
    sn_returned:'Zwrócony',
    sn_defective:'Wadliwy',
    sn_scrapped:'Złomowany',
    prompt_enter_serial:'Wprowadź numer seryjny:',
    prompt_serial_range:'Zakres (np. 1001-1010 lub PRE1001-PRE1010):',
    prompt_enter_lot:'Wprowadź numer partii:',
    prompt_enter_qty:'Ilość:',
    prompt_enter_expiry:'Data ważności (YYYY-MM-DD, opcjonalnie):',
    toast_serial_exists:'Numer seryjny już istnieje',
    toast_invalid_range:'Niepoprawny zakres',
    toast_serials_added:'Numery seryjne dodane',
    // === LOGO ===
    label_company_logo:'Logo firmy',
    btn_upload_logo:'Prześlij logo',
    btn_remove_logo:'Usuń logo',
    logo_help:'PNG, JPG, SVG, WebP — Maks 2MB. Zalecane: 200×200 px kwadrat.',
    toast_logo_too_large:'Plik logo jest za duży (maks 2MB)',
    toast_logo_invalid:'Niepoprawny obraz',
    toast_logo_ready:'Logo gotowe — kliknij Zapisz',
    toast_logo_removed:'Logo zostanie usunięte przy zapisie',
    // === PRODUCT/SERVICE TYPE ===
    label_item_type:'Typ',
    label_product:'Produkt',
    label_service:'Usługa',
    label_all_types:'Wszystkie',
    label_products_only:'📦 Produkty',
    label_services_only:'🔧 Usługi',
    title_add_service:'Dodaj usługę',
    // === SUBSCRIPTION STATUS ===
    status_trial:'Testowy',
    status_expired:'Wygasło',
    status_paused:'Wstrzymano',
    label_no_vat_defined:'VAT niezdefiniowany',
    // === POS RECEIPT ===
    pos_print:'Drukuj',
    pos_receipt_no:'PARAGON',
    pos_cashier:'Kasjer',
    pos_subtotal:'Suma częściowa',
    pos_receipt_thanks:'Dziękujemy!',
    pos_receipt_settings:'Ustawienia paragonu',
    pos_receipt_footer_label:'Tekst na dole paragonu',
    pos_receipt_paper_label:'Rozmiar papieru',
    pos_receipt_show_logo:'Logo na paragonie',
    // === POS RECEIPT MODES ===
    pos_print_mode:'Print Mode',
    pos_print_auto:'Automatic',
    pos_print_ask:'Ask',
    pos_print_none:'Don\'t Print',
    pos_show_subtotal:'Show subtotal',
    pos_show_vat:'Show VAT amount',
    pos_show_cashier:'Show cashier name',
    btn_help:'Pomoc',
    help_projects_title:'Pomoc modułu Projekty',
    help_projects_content:`<h3>Do czego służy ten moduł?</h3>
<p>Służy do osobnego śledzenia prac wykonywanych dla konkretnego klienta w ramach określonego budżetu i czasu. Każdy projekt ma własne przychody, koszty, zysk/stratę i postęp. Gdy kilka prac biegnie równolegle, od razu widać, który jest rentowny, a który ma kłopoty.</p>
<p>Odpowiedni dla firm zarządzających każdym zleceniem jako osobnym pakietem — budownictwo, montaż, kontrakty, doradztwo, agencje itp.</p>

<h3>Kiedy zakładać projekt?</h3>
<p>Załóż projekt, jeśli na 2–3 z poniższych pytań odpowiesz "tak":</p>
<ul>
<li>Czy ta praca ma określony początek i koniec?</li>
<li>Czy zaplanowano dla niej osobny budżet?</li>
<li>Czy potrzebujesz osobnego widoku zysku/straty?</li>
</ul>
<p>Dla jednorazowych drobnych prac lub ogólnych kosztów biurowych projekt nie jest potrzebny. Takie operacje można też zapisywać bez wybierania projektu.</p>

<h3>Tworzenie projektu</h3>
<p>Z menu Projekty przyciskiem <strong>Nowy projekt</strong>. Do uzupełnienia:</p>
<ul>
<li><strong>Nazwa projektu:</strong> krótki, jasny tytuł</li>
<li><strong>Klient:</strong> dla kogo praca, na kogo wystawiane faktury</li>
<li><strong>Kierownik:</strong> odpowiedzialny pracownik</li>
<li><strong>Budżet:</strong> planowany koszt całkowity (tylko orientacyjnie; rzeczywisty jest osobno)</li>
<li><strong>Daty rozpoczęcia i zakończenia</strong></li>
<li><strong>Status:</strong> Planowanie, Aktywny, Zakończony lub Anulowany</li>
</ul>
<p>Numer projektu nadawany jest automatycznie i nie podlega edycji.</p>

<h3>Powiązanie operacji z projektem</h3>
<p>Główna zasada modułu: przy każdej operacji finansowej dotyczącej projektu zaznacz pole <strong>Projekt</strong>. W przeciwnym razie szczegóły projektu nie pokażą poprawnych sum.</p>

<h4>Faktury zakupu</h4>
<p>Dla materiałów lub usług zakupionych na potrzeby projektu:</p>
<ol>
<li>Zakupy → Nowa faktura</li>
<li>Wybierz dostawcę</li>
<li>W polu <strong>Projekt</strong> wskaż właściwy projekt</li>
<li>Uzupełnij pozycje i zapisz</li>
</ol>
<p>Przy importowaniu faktur zakupu z Excela wybór Projektu w kroku 1 powoduje automatyczne powiązanie wszystkich wierszy pliku z tym projektem.</p>

<h4>Faktury sprzedaży</h4>
<p>Przy fakturowaniu klientowi etapów lub wartości robót:</p>
<ol>
<li>Sprzedaż → Nowa faktura</li>
<li>Wybierz klienta (klienta projektu)</li>
<li>Pole <strong>Projekt</strong>: aktywne projekty tego klienta automatycznie pokazują się na górze listy</li>
<li>Uzupełnij pozycje i zapisz</li>
</ol>
<p>Projekt może mieć wiele faktur sprzedaży (zaliczka, faktury etapowe, rozliczenie końcowe). Każdą trzeba osobno powiązać z projektem.</p>

<h4>Operacje bankowe i kasowe</h4>
<p>Zaliczki dla pracownika, płatności dla podwykonawców, drobne wydatki lub wpłaty:</p>
<ol>
<li>Finanse → Bank lub Kasa</li>
<li>Wprowadź dane operacji (kierunek, kwota, kategoria, kontrahent)</li>
<li>W polu <strong>Projekt</strong> wskaż projekt</li>
<li>Zapisz</li>
</ol>

<h3>Śledzenie projektu</h3>
<p>Strona szczegółów projektu ma trzy zakładki:</p>

<h4>Ogólne</h4>
<p>Informacje o projekcie, klient, kierownik, daty i status.</p>

<h4>Finanse</h4>
<ul>
<li><strong>Przychody:</strong> suma faktur sprzedaży powiązanych z projektem</li>
<li><strong>Koszty:</strong> suma powiązanych zakupów, wypływów z banku/kasy, kosztów ręcznych</li>
<li><strong>Wynik netto:</strong> Przychody − Koszty (dodatni = zysk, ujemny = strata)</li>
<li><strong>Wykorzystanie budżetu:</strong> jaki procent planowanego budżetu stanowi rzeczywisty koszt</li>
</ul>
<p>Powyżej 100% wydano więcej niż planowano.</p>

<h4>Operacje</h4>
<p>Wszystkie powiązane sprzedaże, zakupy, operacje bankowe i kasowe w jednej liście chronologicznej. Każdy wiersz pokazuje typ, kontrahenta i kwotę.</p>

<h3>Lista projektów</h3>
<p>Wszystkie projekty na jednym ekranie. W każdym wierszu:</p>
<ul>
<li>Wynik netto (zysk/strata) z kolorystyką</li>
<li>Procent wykorzystania budżetu</li>
</ul>
<p>Dzięki temu od razu widać, który projekt idzie dobrze, a który wymaga uwagi.</p>

<h3>Ważne uwagi</h3>
<ul>
<li><strong>Wybór projektu jest opcjonalny.</strong> Dla operacji niezwiązanych z projektem zostaw puste.</li>
<li><strong>Operację można powiązać tylko z jednym projektem.</strong> Wspólne koszty rozłożone na kilka projektów wprowadź jako osobne wpisy.</li>
<li><strong>Po usunięciu projektu</strong> powiązane operacje nie znikają — odłączane jest tylko powiązanie.</li>
<li><strong>Sprzedaż POS</strong> nie jest wiązana z projektami; służy do obsługi sprzedaży detalicznej.</li>
<li><strong>Aby wynik netto był poprawny</strong>, trzeba powiązać z projektem zarówno przychody, jak i koszty. Gdy oznaczone są tylko koszty, projekt zawsze pokaże stratę.</li>
</ul>

<h3>Funkcje jeszcze nieobsługiwane</h3>
<p>Poniższe funkcje pojawią się w przyszłości:</p>
<ul>
<li>Automatyczny koszt pracy z listy płac i ewidencji czasu</li>
<li>Pełen UI zadań i kamieni milowych</li>
<li>Wykres porównujący budżet i wykonanie w czasie</li>
<li>Wspólne koszty rozdzielane procentowo na wiele projektów</li>
</ul>`,
};
try {
  window.dispatchEvent(new CustomEvent('i18n-loaded', { detail: 'pl' }));
} catch(_) {}
