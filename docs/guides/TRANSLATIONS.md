# Translations

RED's dashboard, its emails and its notification payloads are fully
translatable. This guide covers how the system works and how to add or correct
a locale.

> **Status:** the dashboard, mailers and notifications are extracted and
> translatable. **Eleven locales ship: `en`, `de`, `es`, `fr`, `pt-BR`, `ja`,
> `ru`, `uk`, `pl`, `it` and `zh-CN`.**
> Everything but English is machine-translated and unreviewed — see
> [Review status](#review-status).

## How it works

RED translates through **its own I18n backend**, not the host application's.
`lib/rails_error_dashboard/i18n_store.rb` loads `config/locales/*.yml` into a
private `I18n::Backend::Simple` instance.

This is deliberate. Sharing the host's backend would let a host app break the
error dashboard three ways:

- `config.i18n.raise_on_missing_translations = true` turns any key we forgot
  into a 500 — on the page you need most when things are broken.
- `enforce_available_locales` with a short `available_locales` list raises
  `I18n::InvalidLocale` when RED asks for its own locale.
- A custom `exception_handler` can raise on anything.

The trade-off: **hosts cannot override RED's strings** with their own locale
files. For a self-hosted ops tool that is the right default. It can be relaxed
later without breaking anything.

### Which locale renders

```
RailsErrorDashboard::Current.locale   (per request)
  -> config.dashboard_locale
    -> "en"
```

Every candidate is matched case-insensitively against the locales RED actually
ships. Anything unrecognized falls back to English rather than raising.

The locale is set in an `around_action` and cleared in its `ensure`, so it
cannot outlive the request or leak onto a recycled Puma thread. Pagy's locale is
resolved separately, because Pagy ships a different set of dictionaries — a
locale RED can serve but Pagy cannot still renders, with English pagination.

### Nothing raises

Every lookup falls back to English, then to readable text derived from the key
itself. `red_t("red.nope.missing_key")` renders `"Missing key"` — never
`"translation missing: ..."`, and never an exception. A translation lookup must
never be the reason a dashboard page fails to render.

## Adding a locale

1. Copy `config/locales/en.yml` to `config/locales/<locale>.yml`.
2. Change the root key from `en:` to your locale.
3. Translate the values. Leave the keys alone.
4. Keep every `%{interpolation}` variable exactly as it appears in English —
   a renamed variable is a runtime bug, not a typo.
5. Adjust plural forms to your language's rules — see below. This is the one
   place where your file is *expected* to differ in structure from `en.yml`.
6. Run `bin/i18n-check`, then the test suite.

### Plural forms differ from English on purpose

English has two plural categories (`one`, `other`). French, Spanish and
Portuguese also need `many`. Adding a category English does not have is
correct, and `bin/i18n-check` expects it: plural forms are checked against your
locale's CLDR rules rather than against `en.yml`, so a required `many` is not
reported as an orphan — while a *missing* one is a failure.

This works in both directions. Japanese and Chinese make no grammatical number
distinction and take **`other` alone** — supplying a `one` form for them is the
error, and the checker says so. Because such a group has a single child, the
checker decides what is a plural group by looking at `en.yml`, not by counting
what your file happens to contain: English is authoritative for *which* nodes
are plural, your locale's CLDR rules for *which categories* those nodes need.

Every other key must match `en.yml` exactly.

Filenames are the source of truth for which locales exist:
`I18nStore.available_locales` reads the directory.

### Key conventions

- Keys are `snake_case` and **semantic**, not literal:
  `red.errors.index.empty_title`, not `red.errors.index.no_errors_found`.
- Namespaces: `common`, `time`, `nav`, `errors`, `settings`, `analytics`,
  `health`, `flash`, `mailers`, `notifications`, `js`, `ui_js`.
- **`js` vs `ui_js`** — both end up in JavaScript, but they get there
  differently, and the split is what keeps the payload small. `red.js.*` is
  serialized into `window.RED_I18N` on **every** page load, so it holds only
  what the browser resolves at runtime: month and day names, plural forms whose
  count is not known until the user acts, the relative-time durations.
  `red.ui_js.*` is written into the script body by ERB at render time via
  `red_js_t`, so the browser never looks it up and it costs no payload.

  The test is where the lookup happens, not what the string looks like: if JS
  builds the text at runtime it belongs in `js`; if ERB writes it into the
  script, it belongs in `ui_js`.
- A key ending in `_html` is rendered unescaped. Everything else is escaped.
  Do not add `_html` unless the value genuinely contains markup.

### Strings inside `<script>` blocks

Use `red_js_t`, not `red_t`. `red_t` html-escapes, which is correct for page
text and wrong inside a JavaScript string literal: an apostrophe becomes
`&#39;`, and while `innerHTML` and `showToast` decode that back, `textContent`
renders it verbatim — so a French string shows `d&#39;accéder` on screen.

`red_js_t` runs the value through `escape_javascript` instead, which neutralizes
the quotes, backslashes and line terminators that would break out of or truncate
the literal, and leaves everything the sink will render alone.

### Pluralization

Use nested plural forms driven by `count:`, never a ternary on `"s"`:

```yaml
en:
  red:
    errors:
      count:
        one: "1 error"
        other: "%{count} errors"
```

Supply every plural category your language needs — no more, no fewer. A locale
that omits a category its rules require degrades to English rather than raising,
but that is a safety net, not a plan. For a language whose rules need only
`other`, `other` alone is complete and correct.

### Dates and times

Date formats are translations, not constants — `%B %d, %Y` is a US *ordering*
as much as it is English words. German wants `%d. %B %Y`.

The same patterns are handed to the browser via `data-format` and re-rendered
by `formatDateTime()` in the layout, so only these directives are safe:

```
%Y %y %B %b %m %d %e %A %a %H %I %M %S %p %P
```

A pattern using anything else renders literally in the browser. There is a spec
enforcing this.

Never concatenate a duration and the word "ago" — several languages put the
equivalent first. Use the `red.time.ago` key with `%{duration}`.

## Do not translate

Leave these in English. Translating them breaks debugging, integrations, or
both:

- **Exception class names** (`ActiveRecord::RecordNotFound`) and exception
  messages — diagnostic output, and users search the web for the English text
- **Backtraces**, file paths, SQL, and log output
- **HTTP verbs and status names** (`GET`, `Unprocessable Entity`)
- **Browser and OS names** (Chrome, Safari, Windows, iOS) — brand names.
  "Unknown", "Mobile", "Tablet", "Desktop" *are* translatable
- **Product names**: RED, Rails, Slack, Discord, PagerDuty, GitHub, Sentry
- **Machine-readable payload fields** — PagerDuty `severity`/`event_action`,
  webhook JSON keys, Slack block types. Changing these breaks integrations
- **Issue-tracker bodies** (GitHub/GitLab/Linear) — dev-facing, and the
  maintainer reading them may not share the dashboard's locale
- **Config option names and file paths** (`config/initializers/...`)
- **Audit-trail comment bodies** written by the mute, snooze and status
  commands ("Muted notifications: …"). These are persisted at write time and
  read back later by whoever opens the error — possibly in another locale.
  Translating at write time would freeze one language into the row and leave a
  discussion thread that is half one language and half another. Localizing
  these properly means storing the action and its data as structured fields and
  translating on render, which is a schema change, not an extraction.

### Error-domain terms

The list above is identifiers — things that are obviously not words. This list
is different: these are ordinary English words that developers nonetheless
tend to keep in English, because that is what they search for and what their
language's Rails community says out loud.

Keep these verbatim unless your language's Rails community genuinely uses a
translated form:

| Term | Notes |
|---|---|
| `backtrace` | Not "stack trace" either — RED uses one term throughout |
| `N+1` | Never translated, never spelled out |
| `swallowed exception` | RED-specific; a translated form will not be recognised |
| `deprecation` | |
| `storm` | RED's term for a burst of errors; see the storms page |
| `breadcrumb` | |
| `webhook` | |
| `payload` | |

`bin/i18n-check` **warns** when an English value contains one of these terms
and the translation does not. It warns rather than fails: some languages
inflect or borrow these differently, and a false positive should not block a
release. Treat a warning as a question, not a verdict.

If your language's community does translate one of these, translate it — and
please say so in the PR, so the term can be qualified here rather than
re-flagged on every future locale.

### Recorded departures

| Locale | Term | Rendered as | Why |
|---|---|---|---|
| `ja` | `storm` | ストーム | The ordinary katakana borrowing. RED's sense carries over. |
| `ja` | `swallowed exception` | 握りつぶされた例外 | What Japanese Rails developers actually say. `red.errors.swallowed_page.title` keeps "(swallowed exception)" in parentheses so the English stays searchable. |
| `ja` | `deprecation` | 非推奨 | Only in the nav label and section tab, where space is tight. The page bodies keep "deprecation" alongside the kanji. |
| `ru` | `storm` | шторм | The ordinary Russian rendering; RED's sense carries over. |
| `ru` | `swallowed exception` | подавленное исключение | What Russian Rails developers say. Page titles keep "(swallowed exception)" in parentheses so the English stays searchable. |
| `ru` | `deprecation` | устаревшее / deprecation | Nav and headings use the Russian; bodies keep "deprecation" in parentheses. |
| `uk` | `storm` | шторм | The ordinary Ukrainian rendering; RED's sense carries over. |
| `uk` | `swallowed exception` | придушений виняток | What Ukrainian Rails developers say. |
| `uk` | `deprecation` | застарілий код | Used throughout, including page bodies — Ukrainian has a settled term and mixing in the English read worse than committing to it. |
| `pl` | `storm` | sztorm | The ordinary Polish rendering; RED's sense carries over. |
| `pl` | `swallowed exception` | wyciszony wyjątek | What Polish Rails developers say for an exception rescued and dropped. |
| `pl` | `deprecation` | przestarzały kod | Polish has a settled term; the English adds nothing a Polish reader needs. |
| `zh-CN` | `storm` | 风暴 | The ordinary Chinese rendering; RED's sense carries over. |
| `zh-CN` | `swallowed exception` | 被吞异常 | What Chinese Rails developers say for an exception rescued and dropped. |
| `zh-CN` | `deprecation` | 废弃警告 | The settled Chinese term for the Rails concept. |

These raise `bin/i18n-check` warnings and always will: the check matches ASCII
substrings, so it cannot see a term rendered in kana or kanji. **A glossary
warning on a non-Latin locale is expected, not a defect** — check the value, then
leave it. Only a term genuinely dropped needs fixing.

## Form of address

Pick one register per language and hold it across every string. Machine
translation drifts between formal and informal within a single file, and a
dashboard that addresses you two different ways reads as unfinished.

RED's locales use the formal register, because the audience is someone
operating a production system, often at work:

| Locale | Register |
|---|---|
| `de` | *Sie* |
| `fr` | *vous* |
| `es` | *usted* |
| `pt-BR` | *você* |
| `ja` | **です・ます体** (polite form) |
| `ru` | **вы** (lowercase, formal) |
| `uk` | **ви** (lowercase, formal) |
| `pl` | **Ty** (capitalised, the Polish formal-written convention) |
| `it` | **tu** (the Italian convention for developer tools; *Lei* reads commercial) |
| `zh-CN` | **你** (plain form; 您 reads commercial in developer tooling) |

Japanese has no pronoun to choose here — the register lives in the verb endings,
so the rule is です・ます体 throughout rather than plain form (だ・である体).
Plain form is not rude, but it reads as terse system output; a dashboard telling
an operator what has broken should sound like it is addressing a person. UI
labels and headings stay noun phrases (体言止め) as they do in English —
"設定", not "設定します" — and the polite form applies to sentences: messages,
descriptions, tooltips, confirmations.

If you add a locale, record its choice here so the next contributor matches it
instead of guessing.

## Review status

**German, Spanish, French, Brazilian Portuguese, Japanese, Russian, Ukrainian,
Polish, Italian and Simplified Chinese ship alongside English. All ten are
machine-translated and have not been reviewed by a native speaker.**
RED's maintainer reads only English, so this is stated plainly rather than
described as "beta", which would imply a review process that has not happened.

What this does and does not mean:

- A wrong translation degrades to **English**, never to a broken page — every
  lookup falls back, and nothing in the i18n path raises.
- Key structure, interpolation variables and plural categories **are** verified
  mechanically by `bin/i18n-check` in every locale.
- Wording, register and idiom are **not** verified by anyone.

| Locale | Status |
|---|---|
| `en` | Source language |
| `de` | **Shipped — machine-translated, unreviewed.** [Review wanted →][de-issue] |
| `es` | **Shipped — machine-translated, unreviewed.** [Review wanted →][es-issue] |
| `fr` | **Shipped — machine-translated, unreviewed.** [Review wanted →][fr-issue] |
| `pt-BR` | **Shipped — machine-translated, unreviewed.** [Review wanted →][pt-BR-issue] |
| `ja` | **Shipped — machine-translated, unreviewed.** [Review wanted →][ja-issue] |
| `ru` | **Shipped — machine-translated, unreviewed.** [Review wanted →][ru-issue] |
| `uk` | **Shipped — machine-translated, unreviewed.** [Review wanted →][uk-issue] |
| `pl` | **Shipped — machine-translated, unreviewed.** [Review wanted →][pl-issue] |
| `it` | **Shipped — machine-translated, unreviewed.** [Review wanted →][it-issue] |
| `zh-CN` | **Shipped — machine-translated, unreviewed.** [Review wanted →][zh-CN-issue] |

**Corrections are very welcome, and a one-key PR is a perfectly good PR.** If a
string reads wrong to you, change that string — you are not expected to review
the whole file. Run `bin/i18n-check` before opening the PR and it will catch
the structural mistakes for you. As locales get real attention, this table is
updated and the "unreviewed" qualifier drops from the README.

Each language has an open issue tracking its review — that is where to comment
if you can read it, and they are labelled `good first issue` because they are.
See [Contributing a translation fix](#contributing-a-translation-fix).

[de-issue]: https://github.com/AnjanJ/rails_error_dashboard/issues/156
[es-issue]: https://github.com/AnjanJ/rails_error_dashboard/issues/157
[fr-issue]: https://github.com/AnjanJ/rails_error_dashboard/issues/158
[pt-BR-issue]: https://github.com/AnjanJ/rails_error_dashboard/issues/159
[ja-issue]: https://github.com/AnjanJ/rails_error_dashboard/issues/160
[ru-issue]: https://github.com/AnjanJ/rails_error_dashboard/issues/161
[uk-issue]: https://github.com/AnjanJ/rails_error_dashboard/issues/162
[pl-issue]: https://github.com/AnjanJ/rails_error_dashboard/issues/163
[it-issue]: https://github.com/AnjanJ/rails_error_dashboard/issues/164
[zh-CN-issue]: https://github.com/AnjanJ/rails_error_dashboard/issues/165

## Contributing a translation fix

**You do not need to know Ruby, and you do not need to fix more than one
string.** The most useful contribution to this project's translations is
someone who reads the language noticing that one word is wrong.

There are two ways in, and the first one is genuinely fine:

### 1. Just tell us

Open a [translation correction issue][new-issue]. It asks for the language,
what it currently says, and what is wrong with it. That is enough — you do not
have to find the key or open a PR.

### 2. Fix it yourself

Every string lives in one YAML file per language under `config/locales/`. To
change what the German dashboard says, edit `config/locales/de.yml` — that is
the whole mechanism.

```bash
git clone https://github.com/AnjanJ/rails_error_dashboard.git
cd rails_error_dashboard
bin/setup
```

Find the string. If you can see the English, search for it:

```bash
grep -rn "Unresolved" config/locales/en.yml
#   red: errors: index: filters: status: unresolved: "Unresolved"
```

That dotted path — `red.errors.index.filters.status.unresolved` — is the key.
The same key exists in every locale file, so open `config/locales/de.yml`,
find it, and change the value. **Change only the value, never the key**: the
key is what the code looks up, and renaming it removes the string from every
other language.

Then run the checker:

```bash
bin/i18n-check
```

It takes under a second and catches the structural mistakes that are hard to
see by eye — a broken interpolation variable, a plural category your language
does not allow, malformed YAML. If it exits 0, open the PR.

**A one-key PR is a perfectly good PR.** No wider change is expected of you,
and you do not need to review the rest of the file.

### What makes a good correction

The mechanical properties are already verified by `bin/i18n-check`, so what we
cannot check ourselves — and what we are actually asking you for — is judgement:

- **Meaning.** Does it say what the English says?
- **Register.** RED is formal in every language (see [Form of address](#form-of-address)).
- **Idiom.** Would a developer in your language actually say this? Ops tooling
  has its own vocabulary, and a technically correct translation can still read
  as though nobody in the field wrote it.
- **Terms of art.** Many English words are simply used untranslated by
  developers in other languages. `frame`, `thread` and `query` stay English in
  Italian for exactly that reason — if the loanword is what people say, keep it.

Things that are **not** bugs, so you can skip them:

- A value identical to the English. Roughly a hundred per locale legitimately
  are — brand names, Ruby and Rails identifiers, format strings and cognates.
- Anything on the [do not translate](#do-not-translate) list.
- `bin/i18n-check` glossary warnings on a non-Latin locale. The check matches
  ASCII substrings and cannot see Cyrillic, Chinese or Japanese renderings, so
  those warnings are false positives by construction.

### Adding a language RED does not ship yet

That is a bigger job — around 1,515 keys — and worth
[opening an issue][new-issue] first so we can tell you what the plural rules
for your language will require. See [Adding a locale](#adding-a-locale) for the
mechanics. Two things need adding in Ruby beyond the YAML file: an entry in
`CLDR_CATEGORIES` (in both `bin/i18n-check` and `bin/i18n-merge`) and a
pluralization rule in `PLURAL_RULES` in `lib/rails_error_dashboard/private_backend.rb`.
Ask and we will do that part.

[new-issue]: https://github.com/AnjanJ/rails_error_dashboard/issues/new?template=translation_report.yml

## Testing a locale

Start with the structural check. It runs in under a second and catches the
errors that are hardest to see by eye in a language you do not read:

```bash
bin/i18n-check           # every locale, against en.yml
bin/i18n-check --quiet   # failures only, no advisory warnings
```

It **fails** on a missing key, an orphaned key, an interpolation variable that
does not match English, a plural category your locale's CLDR rules do not
allow (or requires and you omitted), and unparseable YAML.

It **warns**, without failing, on keys nothing appears to reference, a glossary
term that vanished in translation, and English-looking text left in a view.
Warnings are leads, not verdicts — many keys are looked up dynamically and are
invisible to a static scan.

Then the specs:

```bash
bundle exec rspec spec/lib/rails_error_dashboard/i18n_store_spec.rb
bundle exec rspec spec/helpers/rails_error_dashboard/i18n_helper_spec.rb
bundle exec rspec spec/requests/dashboard_locale_spec.rb
```

### Layout testing without a translation

```bash
bin/i18n-check --pseudo   # writes config/locales/qps.yml
```

`qps` accents every letter and pads each string ~30%, which is roughly how much
German runs over English. Anything still rendering in plain English is a string
that was never extracted, and a missing `]` means the text is being clipped.
Interpolation variables are preserved, so the page renders for real.

It is a generated file: do not edit it, and delete it before committing.

Set `config.dashboard_locale` in a host app and load the dashboard. Watch for
layout breakage: translated strings run roughly 30% longer than English in
German, and the sidebar nav and stat tiles are the tight spots.
