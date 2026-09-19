# The RED Case File — open source → business, studied before we try it

> **Research date:** 2026-08-27 · **Status:** first edition · **Companion artifact:** https://claude.ai/code/artifact/42c6c18f-3056-4b12-baa8-964f0c8d98d5
>
> **Question:** RED (rails_error_dashboard) is an MIT Rails engine — 38K downloads, 90 stars, one maintainer, tagline "free, forever", eight months old — that wants Rails shops and enterprises and plans paid Server / Cloud / Enterprise editions. Who tried something like this before, in Rails and across the industry, how did they make money (if at all), and what did their successes and failures teach?
>
> **Note on visibility:** this repository is public. Everything below is drawn from public sources, but the playbook section discusses RED's own pricing and edition design. The maintainer's other strategy analyses (`DEEP_INTROSPECTION_ANALYSIS.md`, `FAULTLINE_COMPARISON.md`) are kept gitignored at the repo root; decide deliberately whether this one is committed.

## Contents

1. [Method and how to read the numbers](#method)
2. [Twelve things the record says](#findings)
3. [Numbers for the wall](#numbers)
4. [Cohort I — Rails-world error monitoring & observability](#cohort-i)
5. [Cohort II — Open source → commercial in Rails and sister ecosystems](#cohort-ii)
6. [Cohort III — Self-hosted error tracking & observability outside Rails](#cohort-iii)
7. [Cohort IV — Solo and tiny-team monetisers ("people like you")](#cohort-iv)
8. [Cohort V — Licences, forks and rug-pulls](#cohort-v)
9. [The promise ledger](#ledger)
10. [What it means for RED — the playbook](#playbook)

---

<a id="method"></a>
## 1. Method and how to read the numbers

Five parallel research passes on 2026-08-27, one per cohort, each using the same per-case template: what/who/when, licence history, money model over time, traction and revenue signals, inflection points, failures and backlash, status today, lessons for RED, sources. GitHub, RubyGems and Docker Hub counts were read live. Company registries (Estonia), SEC/IR filings and press releases were used where they exist; founder blogs, podcasts, Indie Hackers and HN threads for the rest. Each pass ran out of web-search budget near the end; anything it could not confirm is marked.

Provenance tags used throughout:

| Tag | Meaning |
|---|---|
| **reported** | Stated by a third party (press, registry, filing, data vendor with a named method) |
| **claimed** | Stated by the founder or company, not independently checkable |
| **est.** | A data vendor's guess (GetLatka, Sacra, Owler, Tracxn) — treat as noise unless corroborated |
| **unverified** | Recalled or seen in a snippet; primary page not retrieved this session |

Do not repeat a figure from this document without its tag.

---

<a id="findings"></a>
## 2. Twelve things the record says

These are the conclusions that held up across all five cohorts, not the most interesting anecdotes.

1. **No free self-hosted Rails error tracker has ever made money — or survived past ~24 months without a new volunteer.** Errbit (five dark years, revived twice), Errdo, exception-track, Exception Hunter, solid_errors (nine months quiet), Faultline (three months quiet). None tried to charge. RED's paid editions are unprecedented in this niche — the opening, and the reason to expect scepticism.

2. **The money was always in the operated service, never the gem.** better_errors: 109M downloads, $0. exception_notification: 24M, $0. Honeybadger: 40M downloads of its client, "millions." What gets paid for is what the customer can't be bothered to run, support, or get past an audit — never features a fork could copy.

3. **Self-hosted enterprise is where the money is for things people already run.** GitLab self-managed ≈ 71% of ~$1B. Sidekiq: 100% self-hosted, ~$10M, zero employees. Cloud-native vendors that bolted on on-prem retreated (Rollbar); self-hosted-native vendors keep it as core revenue (Grafana, Elastic). RED is born self-hosted. Server is the main event; Cloud is the bolt-on.

4. **Expect ~1% of users to pay, and plan for a Judoscale-sized outcome first.** Grafana monetises ~1% of 20M users. GlitchTip: 3 paying of 258 hosted orgs. Bootstrapped Rails-first monitoring tops out at "millions in ARR" with 3–30 people over 10+ years; the well-run solo Rails add-on plateaus at ~$300K ARR (Judoscale).

5. **Every rug-pull was a broken *prior* promise. "Free, forever" is already a promise.** MongoDB (no promise) survived relicensing; Redis ("BSD will remain BSD") and Elastic ("we will remain open source") were forced to reverse. Decide now what "free, forever" refers to — the gem, not every future product — and write it down before there is anything to protect.

6. **Feature removal hurts more than licence change.** Elastic kept "all free features stay free" and grew through the backlash. MinIO stripped admin from its community console silently and ended "NO LONGER MAINTAINED." Mattermost capped messages in the user's *own* database and got a fork. Nothing that ever shipped in the MIT gem may move out of it.

7. **Persona-based gating is the only tiering rule that survived a decade without a fork.** Perham: "if 100% need it, it goes into core." Sijbrandij: individual-contributor features free, manager features paid, executive features top tier. Everyone who gated something developers need (Oban Web, Spree's copyleft core, Rocket.Chat) reversed it.

8. **The 2026 enterprise self-hosted SKU is standardised. Don't invent one.** Same software + support contract + SSO enforcement/SCIM + RBAC + audit export + compliance evidence + PO/invoice. GlitchTip, SigNoz, Grafana, Bugsnag on-prem, Avo, Chatwoot and Spree EE all sell that exact list. Procurement-shaped features sell; gated core features don't.

9. **Don't sell self-hosting as a one-time purchase, and don't charge for "production use."** Perham's stated biggest regret (Pro was one-time for 18 months). 37signals ONCE reverted to MIT in ~2 years. Bugsink's "production requires a licence" confused buyers and was scrapped in three months. Annual, per-organisation, unlimited seats, under ~$1,000/yr for the first tier.

10. **Distribution beats product in every story; a second person doing marketing is the multiplier.** New Relic: a hosting partner delivered 400 customers on day one. Judoscale: the Heroku marketplace was the entire go-to-market for five years. Xenon on Scout: "great product… not well known." Fider ($1K MRR) vs Plausible ($83K MRR): same shape, one had a full-time content co-founder.

11. **Donations are a rounding error until you're 100× bigger. Solo capacity, not demand, is the limit.** Uptime Kuma: 90K stars, ~$1.6K/yr. Plausible's entire self-host base: $300/month. Fider sold at $1K MRR for "mental space"; Cachet stalled on a family tragedy. "No support" and "community only" tiers are how one person stays solvent.

12. **Solo-maintainer risk is the buyer's real objection — and revenue is the honest answer.** Rails shops will ask "what happens when you stop." Errbit's five dark years and solid_errors' silence are the cautionary tales they already know. Frame the paid tiers as "this is how the project stays maintained" — true, and the strongest enterprise argument RED has.

---

<a id="numbers"></a>
## 3. Numbers for the wall

| Figure | Who | Why it matters to RED |
|---|---|---|
| **~$10M/yr, 0 employees** (claimed) | Sidekiq, ~2,000 customers, 2023–25 | The ceiling for a solo open-core gem business in Ruby. Pro kept under $1,000/yr; Enterprise priced by scale. |
| **€1.18M revenue, 0 employees** (registry) | Hangfire OÜ, 2025 | The .NET twin of Sidekiq; plateaued at ~€1.1M for three years. Comfortable, not compounding. |
| **$22,600 MRR, 1 person, 11 years** (primary) | Healthchecks.io, Aug 2026 | Permissive licence + hosted convenience for a narrow product. Part-time for most of it. |
| **~$300K ARR, 2–3 people, flat since 2021** (claimed) | Judoscale | Steady state of a well-run Rails add-on with marketplace distribution and near-zero marketing. |
| **$300/month** (primary) | Total donations from Plausible's entire self-hosted base, 2024 | Self-hosters do not tip. A paid edition must be a product. |
| **3 paying of 258 hosted orgs** (primary) | GlitchTip, Apr 2021 | When self-hosting is easy, hosted conversion is ~1%. Their fix: paid support for self-hosters. |
| **~1% monetisation of 20M users** (est.) | Grafana Labs, $400M+ ARR | Even a superb product converts ~1%. 38K downloads → low hundreds of payers. |
| **71% of revenue self-managed** (SEC) | GitLab FY2025, $759M | Enterprises pay for software they run themselves. Server > Cloud. |
| **3.5% of users ate the infra team** (primary) | PostHog sunsetting paid Kubernetes, Feb 2023 | Scope Server support to known stacks or the tail eats the maintainer. |
| **3 months** | Bugsink's "production use requires a licence," Oct 2024 → Jan 2025 | A solo self-hosted tracker's paid-for-production model confused buyers and died fast. |
| **~15 months** | Spree's AGPL core, Sep 2024 → early-2026 reversal | Relicensing the core to force enterprise deals fails in Rails; proprietary modules around a permissive core stuck. |
| **90.7K stars → ~$1.6K/yr** (ledger) | Uptime Kuma | Stars are not a funnel without an offer. Retrofitting a paid tier onto a 90K-star MIT project is politically impossible. |
| **9 of 24 contributors left** (Percona) | Redis after the 2024 relicense | Forks are made of people. RED's equivalent asset is its contributors and the Rails community's blessing. |
| **−40% docs traffic, −80% revenue** (primary) | Tailwind Labs, Jan 2026 | Don't build on a docs-traffic funnel; AI assistants bypass docs. Put the upsell inside the product. |
| **$50K/yr lost overnight** (primary) | Caleb Porzio, GitHub Sponsors drops PayPal, Jan 2023 | Own the payment rail and the customer list. Never one platform. |
| **~$25–30/mo** | Sentry Team $26 · Honeybadger Team $26 · elmah.io $26 · Flare €29 | The market anchor for a team error tracker. Indie floor: RorVsWild €10/mo. |
| **$75–$249/app/mo, no per-seat** | Avo | The Rails-validated price band for an engine sold per app to shops. |
| **$10K–$100K grants** | FLOSS/fund (Zerodha), $1M/yr, apply via `funding.json` | Highest expected value of any non-product channel at RED's size. |

---
<a id="cohort-i"></a>
## 4. Cohort I — Rails-world error monitoring & observability

RED's direct ancestors and neighbours. GitHub/RubyGems numbers pulled live 2026-08-27. Pattern in one line: *every free self-hosted tracker stalled; every business was hosted; every exit was a tuck-in for the customer list.*

### Errbit
- **What / who / when:** Open-source, self-hosted, Airbrake-API-compatible error catcher. Repo created 2010-08-04 by Jared Pace (Relevance, "open-source Fridays"). Rails app + MongoDB. Solo creator, then a rotating cast of volunteer maintainers (ndbroadbent, shingara, stevecrozz, arthurnn, nashby).
- **License history:** MIT from day one; never changed.
- **Money model over time:** None, ever. No sponsors page, no hosted edition, no support contracts. The only "hosting" is a Heroku deploy button and third-party VPS templates with no relationship to the maintainers. Treat "hosted attempts" as nonexistent, not failed.
- **Traction & revenue signals:** 4,271 stars, 989 forks, 4,241 commits, 144 open issues (2026-08-27). Revenue: $0.
- **Inflection points:**
  - 2011–2013: rode the Hoptoad → Airbrake → Exceptional → Rackspace churn. Every acquisition-driven wobble at Airbrake sent people to Errbit, because the notifier gem was already installed — they only changed a URL.
  - 2014–2018: stevecrozz era; v0.7/v0.8 line.
  - **The stall:** v0.9.0 shipped 2020-03-16 and then nothing for five years. Commits: 11 in 2020, 43 in 2022, 6 in 2023, 3 in 2024. Frozen on Ruby 2.5.1 and Rails 4.2.11.1 with known CVEs in dependencies.
  - **The revival:** Ihor Zubkov (biow0lf) took over: v0.10.0 on 2025-04-16 (Ruby 3.4.3, Rails 7.2, Zeitwerk, GitHub Actions, Thruster). 899 commits in 2025, 466 so far in 2026. v0.11.0 (2026-06-10) moved to Ruby 4.0.5 / Rails 8.1.3 and is "the last branch that supports MongoDB." Latest v0.11.4 (2026-08-13). 2025–26 "alternatives" roundups still say "not recommended for new projects."
- **Failures / mistakes / backlash:**
  - MongoDB as a hard dependency — the single biggest adoption tax; why `errbit-postgres` forks exist and why the project is migrating off it 15 years later.
  - A *separate app to deploy* rather than an engine: "intended for people with experience deploying and maintaining Rails applications."
  - Airbrake-API compatibility was both the growth hack and the ceiling: feature set defined by someone else's wire protocol, and Airbrake's own notifier gem is now stale (last commit 2024-12-13).
  - Bus factor of one, repeatedly. The five dark years were a governance failure, not a technical one.
- **Status today (2026):** Actively maintained again by one volunteer, releasing monthly, mid-migration off MongoDB. Still MIT, still $0.
- **Lessons for RED:**
  - RED's architecture (engine inside the host app, host DB, no Mongo) is exactly the fix for Errbit's two adoption killers. Say so: "Errbit without the second deployment."
  - Errbit proves self-hosted Rails demand is durable (4.3K stars across 16 years, revived twice) — and that nobody has ever monetised it. The gap has been open since 2010.
  - Own the schema so paid features aren't constrained by a legacy protocol.
  - Plan succession before you need it: document the release process; add a second maintainer with release rights early.
- **Sources:** https://github.com/errbit/errbit · https://github.com/errbit/errbit/releases · https://errbit.com/blog/ · https://www.hostinger.com/applications/errbit · https://danubedata.ro/blog/self-host-sentry-glitchtip-error-tracking-2026

### Hoptoad → Airbrake
- **What / who / when:** Built inside thoughtbot in 2007, public 2008 as Hoptoad — "the first exception monitoring service in the world" (Airbrake's claim). Consultancy side project.
- **License history:** SaaS; notifier gem MIT (`hoptoad_notifier` → `airbrake`, 50.2M downloads, last commit 2024-12-13).
- **Money model over time:** Paid SaaS from 2008; early Heroku add-on. Sold Feb 2012 to Exceptional Cloud Services (Jonathan Siegel); ECS sold to Rackspace March 2013; spun out as independent 2015 (reported); $11M led by Elsewhere Partners, April 2020 (reported); acquired by LogicMonitor 2021-02-23, terms undisclosed. Freemium/PLG under LogicMonitor; pricing from $19/mo (2026).
- **Traction & revenue signals:** "Over one billion exceptions caught" at the July 2011 rename (claimed). "150,000 requests per minute" at peak (claimed). Exceptional + Airbrake combined: 75,000 customers, 5B errors (TechCrunch 2012, reported). No revenue ever disclosed.
- **Inflection points:**
  - Being first, and being thoughtbot's — the notifier shipped in every thoughtbot client app and every Rails tutorial.
  - July 2011: forced rename (a trademark holder "over all things related to frogs and toads") — brand equity reset.
  - 2011–12: thoughtbot said running it "was like being under a constant DoS attack" and that they "spent very little time working toward our vision." Honeybadger's founders name Airbrake's 2011–12 decline (spinners instead of errors, "nonexistent" support) as the reason they founded Honeybadger. HN threads on the sale: "just run Errbit."
  - Four owners in nine years. Each transition leaked customers to Honeybadger, Errbit, Sentry, Rollbar, Bugsnag.
- **Failures / mistakes / backlash:** A consultancy could not fund the infrastructure a high-volume ingest product needs; support collapsed; brand rebuilt twice; the official Ruby gem stale for 20 months under LogicMonitor.
- **Status today (2026):** A product line inside LogicMonitor; 20+ languages; no EOL announced.
- **Lessons for RED:**
  - The *ingest* problem thoughtbot drowned in is the one RED structurally avoids (errors never leave the host app). A real cost advantage for a paid self-hosted edition — RED never pays for the customer's error volume.
  - Every ownership change of an incumbent is a customer-acquisition event for the alternatives. Time paid-edition launches to Sentry/Honeybadger/AppSignal pricing shocks and acquisitions.
  - Trademark-check any distinct brand before launch. "Rails Error Dashboard" is descriptive (safe) but weak.
- **Sources:** https://thoughtbot.com/blog/hoptoad-is-now-airbrake · https://thoughtbot.com/blog/airbrake-acquired-by-exceptional · https://techcrunch.com/2012/02/07/exceptional-acquires-error-tracking-application-airbrake/ · https://techcrunch.com/2013/03/28/rackspace-acquires-exceptional-to-add-app-error-tracking-tools-for-developers/ · https://www.siliconhillsnews.com/2020/04/10/airbrake-raises-11-million-in-funding/ · https://www.apmdigest.com/logicmonitor-acquires-airbrake · https://podcast.thoughtbot.com/443 · https://github.com/airbrake/airbrake

### Exceptional (Contrast → Exceptional Cloud Services)
- **What / who / when:** Hosted exception tracker for Rails, spun out ~2009 from Contrast, the Dublin design consultancy of Eoghan McCabe, David Rice, Des Traynor, Ciaran Lee. Gem repo created 2008-06-19.
- **Money model over time:** Paid SaaS. Sold 2011 to Exceptional Cloud Services (Jonathan Siegel) — proceeds seeded Intercom. ECS then bought Airbrake (Feb 2012) and Redis To Go, and sold the bundle to Rackspace (March 2013). Exceptional.io shut down 2016-09-01 "in favor of Airbrake."
- **Traction:** 6,000+ apps tracked, 50,000+ developers (Rackspace/TechCrunch 2013, reported). No revenue figures.
- **Status today (2026):** Dead since 2016. The Jonathan Siegel who ran ECS appears to be the same Jonathan Siegel who is a General Partner at Xenon Partners, which bought Scout APM in 2019 (name and bio match; not independently confirmed) — a repeat roll-up buyer in this niche.
- **Lessons for RED:** A Rails error tracker is a plausible acquihire/roll-up asset even at modest scale. Roll-ups kill products; if the goal is a lasting product, an acquisition is not the win condition.
- **Sources:** https://en.wikipedia.org/wiki/Intercom,_Inc. · https://www.cbinsights.com/investor/exceptional-cloud-services · https://github.com/exceptional/exceptional

### Honeybadger
- **What / who / when:** Hosted exception + uptime + cron monitoring, launched October 2012 by three Rails consultants: Josh Wood, Ben Curtis, Starr Horne. Built because Airbrake "deteriorated in quality and customer support around 2011."
- **License history:** SaaS; `honeybadger` gem MIT (40.0M downloads, 6.9.1 released 2026-07-16).
- **Money model over time:** Paid SaaS from launch, $0 outside capital, 100% founder-owned. Started "underpriced," moved to tiered pricing, then grew by "enforcing generous but meaningful volume limits" with errors/month as the value metric. Current: Developer free (5K errors/mo), Team $26/mo (50K), Business $80/mo (SOC2/HIPAA/SAML), Enterprise custom with "single-tenant or self-hosted deployment" (sales-only). AWS Marketplace listing April 2026. Adjacent: Hook Relay, Honeybadger Insights (logs/APM), status pages, a hosted MCP server (Aug 2026, with EU self-hosting).
- **Traction & revenue signals:** "Over $1M ARR… sub-1% monthly churn" (Josh Wood, Indie Hackers podcast 2019 — claimed). "Millions in lifetime revenue" (IH AMA 2021 — claimed). Infra $80/mo at launch → ~$10K/mo by 2021 (claimed). Founders drew part-time pay at 18 months, full-time in 2014. "Never more than five full-time developers at one time" (Ruby Central 2025 — claimed). Logos: DigitalOcean, Vimeo, Zappos.
- **Inflection points:**
  - Market timing: an incumbent failing its users, and an initial email to "~100 Rails developers" in Ben's network.
  - Bundling (errors + uptime + cron + logs + APM in base tiers) versus Sentry's per-product metering — at $26/mo both include 50K errors; the difference is what happens at error 50,001 (Sentry meters, Honeybadger steps you up a tier).
  - Content marketing at scale (a large Ruby/Python tutorial blog), FounderQuest podcast, GitHub Student Developer Pack, conference sponsorship, stickers/shirts.
  - Recent enterprise moves: SOC2, HIPAA, SAML, AWS Marketplace, self-hosted enterprise option, MCP.
- **Failures / mistakes (founders' own words):** priced too low initially; built without early validation; all-developer founding team; "over-focused on shipping rather than measuring"; "formal user acquisition" the weak area. Deliberately "sacrificed some growth in exchange for a healthier, happier lifestyle."
- **Status today (2026):** Independent, profitable, ~5 devs plus staff, shipping monthly. **Honeybadger is the named sponsor in the README of solid_errors** — the incumbent funds the free self-hosted competitor and recommends it for people who "just want simple."
- **Lessons for RED:**
  - The 2012 wedge was "the incumbent got bad." RED's 2026 wedge is "you don't want your errors leaving the building" — but the playbook (a personal network of ~100 Rails devs, student-pack programs, out-write everyone) is directly reusable.
  - Honeybadger's enterprise tier already sells "self-hosted deployment" behind sales. RED must be cheaper or more transparent (published pricing) to win it.
  - Sub-1% churn came from being a *utility*; favours a low-price, high-volume paid edition over a high-touch one.
  - Consider asking Honeybadger to sponsor RED, as they sponsor solid_errors. Their logic: self-hosted minimalists were never going to pay them. Which is also the warning: the incumbent regards the self-hosted segment as non-monetisable.
- **Sources:** https://www.indiehackers.com/podcast/122-josh-wood-of-honeybadger · https://www.indiehackers.com/post/three-co-founders-nine-years-millions-in-lifetime-revenue-ama-f360db79a2 · https://rubycentral.org/news/company-spotlight-how-honeybadger-built-a-profitable-bootstrapped-business-on-rails/ · https://www.honeybadger.io/plans/ · https://aws.amazon.com/marketplace/pp/prodview-yozbmqhcmlrkm · https://github.com/fractaledmind/solid_errors

### AppSignal
- **What / who / when:** Amsterdam, 2012. Roy Tomeij, Thijs Cadier, Wes Oudshoorn. Rails APM + error tracking; later Elixir, Node, Python, Java, logs.
- **License history:** SaaS; `appsignal` gem MIT (19.8M downloads).
- **Money model over time:** Bootstrapped paid SaaS for 13 years; request-based pricing with a permanent free plan (50K requests/mo). May 2025: $22M (€19.5M) Series A from Elsewhere Partners — the same firm that funded Airbrake in 2020. New CEO Brandon Swalve; Roy Tomeij to board; US HQ in Austin. Founders: "every funding conversation went down a rabbit hole of trying to turn the business into something it wasn't."
- **Traction & revenue signals:** 2,000+ customers in 60+ countries; "over 100 billion requests a month"; "millions in ARR" (claimed 2025). ~25–30 employees.
- **Inflection points:** Deep Ruby/Rails community investment (Rails Foundation, sponsorships, a very large tutorial blog); product simplicity; multi-language expansion; the 2025 raise for the US mid-market and OpenTelemetry.
- **Lessons for RED:**
  - Thirteen years of bootstrapping in this exact niche produced "millions in ARR" and a $22M round — the ceiling is real but modest, and reaching it took over a decade with three founders.
  - Elsewhere Partners has bought into two Rails-origin monitoring companies. If RED ever wants growth capital, that is the buyer profile.
  - AppSignal's free tier is a *usage* cap, not a feature cap — cheap because they own the ingest. RED's customer already pays for their own DB.
- **Sources:** https://www.appsignal.com/appsignal-closes-usd-22-million-growth-investment · https://thefoundingjourney.substack.com/p/13-years-bootstrapped-then-22m · https://www.appsignal.com/about

### Skylight (Tilde Inc.)
- **What / who / when:** Rails-only production profiler/APM from Tilde (Portland; Yehuda Katz, Carl Lerche, Tom Dale, Leah Silber). Announced RailsConf 2013; agent has a Rust core.
- **License history:** SaaS; `skylight` gem source-available, not OSI-licensed. 13.1M downloads; 7.1.1 released 2026-04-17.
- **Money model over time:** Paid SaaS subsidised by consulting, "bootstrapped, investor-free… we wanted the ability to control our own destiny" (2014). 100,000 free traces/month, paid from $20/mo. Free for open-source apps since Feb 2018.
- **Traction & revenue signals:** No customer or revenue numbers ever published.
- **Inflection points:** Yehuda's Rails-core credibility got it a hearing; low-overhead agent and 95th-percentile-first UI were genuinely differentiated in 2013–15. Then: no expansion beyond Ruby, no error tracking, no logs. Yehuda "spent a decade at Tilde" and now works at Heroku.
- **Failures:** Too narrow a niche to fund a team without consulting; the product never broadened. The clearest example of a superb Rails-only product that stayed a lifestyle side-business.
- **Status today (2026):** Alive, still releasing, handling incidents; no visible product or company news since ~2020.
- **Lessons for RED:**
  - Rails-only APM is a viable *sustained* niche but has never produced a public number. RED's "Rails shops and enterprises" goal needs a second distribution axis (hosting partners, agencies, Hotwire/Kamal ecosystem) that Skylight never built.
  - Consulting-subsidised product is a slow death for the product.
  - Free-for-OSS was Skylight's best marketing move; RED could offer free Server licences to OSS Rails projects (Mastodon, Discourse, Forem).
- **Sources:** https://www.tilde.io/skylight/ · https://blog.skylight.io/announcing-the-skylight/ · https://www.skylight.io/pricing · https://yehudakatz.com/about/ · https://github.com/skylightio/skylight-ruby · https://news.ycombinator.com/item?id=16341813

### Scout APM
- **What / who / when:** Founded 2008 by Derek Haynes, Andre Lewis, Charles Brian Quinn (Highgroove Studios, Atlanta). Server monitoring first; Scout APM for Rails ~2015 as a "New Relic alternative."
- **Money model over time:** Bootstrapped SaaS. May 2017: server-monitoring product sold to SolarWinds (→ Pingdom Server Monitor). July 2019: Scout APM acquired by Xenon Partners (PE). April 2021: $8M from Camber Partners; acquired Exceptiontrap for error monitoring. 2022: TelemetryHub. 2026: repositioned as "AI-native" APM with MCP/CLI access; "no per-seat pricing."
- **Traction & revenue signals:** None public. Xenon's own words: "a great product and scalable technology that was previously not well known in the APM user community."
- **Failures:** Founders sold twice rather than scale — a Rails-first APM couldn't reach venture scale, and PE rolled it up.
- **Lessons for RED:**
  - "Great product, not well known" is the modal fate. RED's constraint is distribution, not features.
  - MCP/agent access to error data is table stakes (Scout, Honeybadger, Faultline). RED's local-DB architecture makes an MCP server trivially private — a real enterprise differentiator.
- **Sources:** https://www.prweb.com/releases/xenon_partners_announces_acquisition_of_scout_apm/prweb16454335.htm · https://www.prweb.com/releases/scout-apm-raises-8mm-acquires-exceptiontrap-812244394.html · https://www.globenewswire.com/news-release/2017/05/17/986854/0/en/ · https://scoutapm.com/

### New Relic (RPM — Rails Performance Management)
- **What / who / when:** Founded 2008 by Lew Cirne after selling Wily Technology (Java APM) to CA for $375M. Began as his "teach-myself-Ruby-on-Rails project." Benchmark-backed from the start.
- **Money model over time:** Paid SaaS (RPM GA May 2008); free "RPM Lite" Sept 2008; $6M Series B Nov 2008; expanded to Java/PHP/.NET/Python 2010–11; IPO December 2014; FY2023 revenue $926M (reported, SEC); taken private by Francisco Partners + TPG for ~$6.5B, completed 2023-11-08.
- **Traction & revenue signals:** "An average of 170 new customers per month" after launch and "more than 1,400 customers" on RPM Lite in its first two months (press releases, claimed). A Rails hosting partner "brought 400 customers on day one" (Cirne; likely Engine Yard, unconfirmed). "~85% share of the APM market in the Rails space within eight months" (claimed). 37signals as launch reference customer.
- **Inflection points (Cirne's account):**
  - Rails chosen as "a market small enough to dominate, easy to reach the thought-leaders."
  - Pre-launch: "It just can't be all product" — he worked the Rails core/37signals circle for references before shipping.
  - Distribution through hosting partners and a free tier four months after launch.
  - "You have about 180 seconds to wow the new customer, and the timer starts as soon as they sign up."
  - Left the Rails-only box within two years.
- **Failures:** Later pricing complexity and the 2020 "New Relic One" repricing alienated many small Rails shops (widely discussed; not re-sourced).
- **Lessons for RED:**
  - The playbook is not "Rails forever"; it is "Rails as the beachhead, hosting partners as the channel, free tier as the funnel." Borrow the *channel* idea even while staying Rails-only.
  - "180 seconds" applies literally: `bundle add` → mount → see an error should be the whole demo.
  - Cirne had references from 37signals and Rails core on launch day. Pursue a Rails-core-adjacent endorsement deliberately.
- **Sources:** https://newrelic.com/press-releases/20080529 · https://newrelic.com/press-releases/20080916 · https://newrelic.com/press-releases/20081112 · https://growfers.com/story/new_relic/ · https://www.startlaunchgrow.com/lew-cirne-interview-part-1/ · https://newrelic.com/press-release/20231108

### Rollbar
- SF, 2012, Brian Rue and Cory Virok. VC SaaS: $17.4M total; $11M Series B led by Runa Capital, March 2020. "Over 100,000 developers, more than 4,000 customers" (2020, claimed). Still independent and founder-led in 2025; shipped Session Replay Oct 2025. No exit.
- **Lesson:** Modest VC in this category buys a long plateau, not an outcome; 4,000 customers at $17M raised is a useful upper-bound sanity check for a multi-language hosted tracker that doesn't become Sentry.
- **Sources:** https://www.prnewswire.com/news-releases/rollbar-secures-11-million-series-b-to-help-engineering-teams-release-more-often-301016070.html

### Bugsnag
- ~2012, James Smith and Simon Maynard. $1.4M seed, $7.2M Series A (Benchmark, 2015); per-seat from $29/mo; 22,000 developers (2015); 6,000+ organisations and 1B+ crash reports/day (2021, claimed). Acquired by SmartBear (Vista-backed) 2021-04-28. Smith: "a no-brainer for us and our customers."
- **Lesson:** Error-tracking exits are tuck-ins into larger tool suites — buyers want the customer list, not the code. An MIT codebase doesn't reduce that value.
- **Sources:** https://techcrunch.com/2015/07/07/bugsnag-nabs-7-2-million-in-series-a-funding-from-benchmark/ · https://smartbear.com/news/news-releases/smartbear-adds-enterprise-grade-stability/

### Raygun (Mindscape)
- Wellington, NZ. Mindscape founded 2007 with $10K each from three founders; Raygun launched 2013 out of .NET-tooling revenue (a $250K Microsoft NZ contract on day one). First outside capital 2014; $1.7M total; cash-flow positive. "Several million dollars" ARR, ~50 staff, blog at 200K monthly visitors (all claimed). Churn "primarily from startup shutdowns."
- **Trask's lessons:** "No silver bullets, lots of lead bullets"; small 50–100 person meetups convert far better than big conferences; "cash is your air supply."
- **Lesson for RED:** A services-funded tracker can reach "several million" ARR — over 12+ years and by leaving its platform niche. Raygun's channel mix (content > meetups > podcasts > small conferences > social > tiny AdWords) is the most concrete bootstrapped-marketing recipe in this cohort.
- **Sources:** https://raygun.com/blog/story-raygun/ · https://saasclub.io/podcast/raygun-founder-from-developer-to-saas-entrepreneur/

### RorVsWild (Base Secrète)
- **What / who / when:** Geneva. Alexis Bernard (engineering) and Antoine Marguerie (design), a two-person Rails shop. Gem repo 2014-11-19. Rails-only APM + errors + jobs + server metrics.
- **License history:** SaaS; `rorvswild` gem MIT (557K downloads; 1.12.0 July 2026). The gem doubles as a free **local development profiler** that works without an account.
- **Money model:** Bootstrapped paid SaaS, "100% independent. No trackers." Pricing: €10/mo + €10 per extra 1M requests/jobs; €100 (10M); €300 (50M); €400 + €1/M (100M+). Unlimited apps and developers on every plan. Positioning: "The one-person framework monitoring tool."
- **Traction:** None published. 388 stars.
- **Lessons for RED:**
  - The closest living analogue to RED's paid-edition idea in *scale*. Eleven years in, no numbers — assume a good living, not a company.
  - The free-local-profiler-as-funnel is transferable: RED's OSS edition *is* the funnel. Copy the pricing shape (per-volume, unlimited seats).
  - €10/mo is where indie Rails devs' willingness-to-pay sits.
- **Sources:** https://www.rorvswild.com/ · https://github.com/BaseSecrete/rorvswild · https://basesecrete.com/about/

### Judoscale (formerly Rails Autoscale)
- **What / who / when:** Adam McCrea, solo. First commit July 2016 (at his employer), alpha Jan 2017, GA on the Heroku Marketplace Dec 2017 (Heroku required 100 beta customers first — 11 months). Rebranded Judoscale 2021; TinySeed Spring 2021 ($120K). Not error tracking, but the best-documented bootstrapped Rails add-on business.
- **Money model over time:** Heroku add-on billing; 7-day trial → freemium June 2021; expanded to Render, Fly.io, Railway, ECS and to Python/Node/Java.
- **Traction & revenue signals:** Under $5K MRR at start of 2020 → $15K+ end of 2020 → $26K MRR / ~$300K ARR and 500+ customers by June 2021 (claimed, Startups for the Rest of Us ep. 556). Sept 2025: "$300,000 in annual recurring revenue" (claimed) — if accurate, flat for four years while the team grew to Adam + Carlos Antonio da Silva (Rails core).
- **Inflection points:** Heroku Marketplace as the *entire* distribution channel for five years ("I don't think I did anything to market it. I waited for customers to come"); Heroku shipping a free native autoscaler as the existential platform-risk moment; the rename forced a new add-on listing and the old name still out-ranks the new one in search.
- **Failures (his words):** No written IP agreement with the employer where it was born (fixed years later); minimal marketing; "I am a developer by trade, I'm not a marketer."
- **Lessons for RED:**
  - Marketplace distribution turned a solo side project into $300K ARR with near-zero marketing. List RED's Cloud edition wherever Rails apps are deployed.
  - Renaming away from "Rails" cost search rank for years. Keep the gem name and add a brand.
  - Get any employer IP assignment in writing before a paid edition.
  - "$300K ARR, three people" appears to be the steady state for a well-run Rails add-on. Plan the paid editions around that reality, not a Sentry-shaped one.
- **Sources:** https://www.startupsfortherestofus.com/episodes/episode-556-rails-autoscale · https://www.buzzsprout.com/2509083/episodes/17750895-adam-mccrea-judoscale · https://www.founderquestpodcast.com/episodes/scaling-judoscale-with-adam-mccrea/transcript · https://www.indierails.com/16

### solid_errors (Stephen Margheim / fractaledmind)
- **What / who / when:** "DB-based, app-internal exception tracker for Rails" on the `Rails.error` API. Repo 2024-01-14; announced 2024-01-28. Solo author with a full-time day job (Principal Engineer at Impruvon Health from Nov 2025).
- **License:** MIT.
- **Money model:** None. GitHub Sponsors badge; **Honeybadger is the named "Proudly sponsored by" logo** (Honeybadger and Hatchbox also sponsored his High Leverage Rails course). No paid tier, no hosted version.
- **Traction:** 488 stars, 32 forks, **379,444 gem downloads (≈10× RED's 38K)**; v0.7.0 2025-06-11 ("almost entirely community-driven"); last push 2025-11-24; 23 open issues.
- **Inflection points:** Rode the "Solid *" naming wave and the Rails 7.1/8 error-reporter API; an explicit non-goal list ("you can view and resolve errors. That's it… if you need more, use a 3rd party service like Honeybadger") made it the default "just enough" option.
- **Status:** Nine months without a commit; maintainer has a newborn and a new job; community-carried.
- **Lessons for RED:**
  - solid_errors defines the floor: 10× RED's downloads with a fraction of the features, because it is the *simplest* option and rides Rails naming. RED cannot out-simple it; RED is the "you outgrew solid_errors" destination — say so, offer a migration rake task.
  - Honeybadger sponsoring the minimal free tracker is a tell: incumbents see self-hosted-minimal as a lead source. RED's paid tier is the first thing in this sub-niche that actually competes with them.
  - Solo maintainers with day jobs stall at ~18 months (solid_errors, Exception Hunter, Errdo). RED's monetisation is the answer to its own bus factor — frame it that way.
- **Sources:** https://github.com/fractaledmind/solid_errors · https://fractaledmind.com/2024/01/28/introducing-solid-errors/ · https://fractaledmind.com/2025/12/31/year-in-review/

### Faultline (dlt)
- **What / who / when:** "MCP-powered, self-hosted embedded error tracking Rails engine" — Rails 8+, Rack middleware + `Rails.error` capture, local-variable capture, side-by-side "Debugger Inspector," GitHub issue creation, Telegram/Slack/Discord/email/webhook notifiers, experimental APM, built-in MCP server. Repo 2026-01-10; solo.
- **License / model:** MIT. Marketing copy: "genuinely free… no premium tier, no per-error pricing, no feature gating."
- **Traction:** 87 stars, 114 commits; last push 2026-05-14 (three months quiet). No RubyGems release — the `faultline` gem (49,631 downloads, v0.2.0, 2017) is an unrelated older gem with a name collision.
- **Lessons for RED:**
  - Faultline's feature list is the 2026 expectation bar for a self-hosted Rails tracker. Ship an MCP server before the paid editions.
  - "No premium tier ever" attracts users who will never pay and then strands them when the author moves on. RED's posture: "free-forever core, paid so it stays maintained."
- **Sources:** https://github.com/dlt/faultline · https://dlt.github.io/faultline/

### Exceptiontrap (itmLABS → Scout APM)
- Hosted error tracking for Rails and PHP by Torsten Bühl; gem 2012; sold as Heroku, Engine Yard and cloudControl add-on. Acquired by Scout APM April 2021 as part of Scout's $8M round, to become Scout's error-monitoring feature. Dead as a brand.
- **Lesson:** A one-person hosted Rails tracker with a marketplace channel was worth acquiring as a *feature* by a PE-owned APM. A realistic small-exit path, and a ceiling.
- **Sources:** https://github.com/itmLABS/exceptiontrap · https://addons.engineyard.com/addons/exceptiontrap

### Exception Hunter (Rootstrap), Errdo, exception-track, activeerror — the graveyard
- **Exception Hunter:** Postgres-backed Rails engine with Devise-gated dashboard, published 2020-07-23 by the agency Rootstrap "for hobby projects and small MVPs that cannot justify paid monitoring." MIT. 82 stars, 61K downloads; last commit 2021-10-18. Dead. Postgres-only and Devise-coupled.
- **Errdo** (Eric Haydel): engine created 2016-07-15; last push Jan 2019; 87 stars, 56K downloads. Two breaking schema changes in a row (0.10→0.11→0.12) with manual migration steps.
- **exception-track** (huacnlee): DB-backed tracker on `exception_notification`, 2017–2021; 118 stars, 159K downloads. Dead.
- **activeerror** (npezza93): tiny engine, still pushed 2026-04; 5 stars.
- **Common thread:** every DB-backed in-app Rails error tracker before RED was a solo/agency side project that shipped for 12–24 months and stopped. None attempted monetisation. None had a second maintainer. RED (created 2025-12-24) is eight months in — at the exact point on that curve.
- **Lessons for RED:** The differentiator RED can offer is the one none of them tried: a revenue reason to keep going. Ship a stable migration story (Errdo's failure class is the same as RED's own installer-timestamp bug). Offer importers from `exception_hunter`/`errbit` tables to pick up stranded users.
- **Sources:** https://github.com/rootstrap/exception_hunter · https://github.com/erichaydel/errdo · https://github.com/rails-engine/exception-track · https://github.com/npezza93/activeerror

### exception_notification and better_errors — free-forever reference points
- **exception_notification:** Jamis Buck, 2005, Rails core plugin; maintained by smartinez87 from ~2011; handed to Kevin McPhillips in 2025 (v5.0.1 Aug 2025). 24.0M downloads. README: "not under active development, but is maintained… there are more robust and modern solutions." Never monetised.
- **better_errors:** Charlie Somerville, Dec 2012; 6,862 stars, 109.1M downloads; last commit 2023-06-14. Never monetised.
- **Lessons for RED:** Ubiquity in the Rails ecosystem has never converted to money on its own; the monetisable layer has always been the operated part. RED's notifications compete with `exception_notification`'s core use case — a one-line migration guide is cheap acquisition.
- **Sources:** https://github.com/kmcphillips/exception_notification · https://github.com/BetterErrors/better_errors

### Patterns across Cohort I
1. Every free self-hosted Rails error tracker has died or stalled at 12–24 months, and none tried to make money. The single revival (Errbit 2025) came from a new volunteer, not a business model.
2. The money in this category has always been in the operated service, never the gem. Paid Server/Enterprise editions must sell *operations* (upgrades, retention, SSO, compliance, support, MCP privacy) rather than features a fork could copy.
3. Bootstrapped Rails-first monitoring tops out around "millions in ARR" with 3–30 people, and takes 10+ years. Plan for a Judoscale/RorVsWild-sized outcome first.
4. Distribution beats product in every story. Get listed where Rails apps are deployed; out-write the incumbents.
5. Incumbent turbulence is the recurring wedge; time paid launches to competitor pricing/acquisition news.
6. Exits are tuck-ins for the customer list, and the product usually dies or fades. One buyer profile recurs (Siegel/Xenon; Elsewhere Partners).
7. Solo-maintainer risk is the buyer's real objection, and revenue is the honest answer.
8. 2026 table stakes: MCP/agent access, local-variable capture, SOC2-style controls, EU data residency. RED's in-app architecture makes MCP, residency and "no third party ever sees the data" free to claim — headline the Enterprise edition with them.

---
<a id="cohort-ii"></a>
## 5. Cohort II — Open source → commercial in Rails and sister ecosystems

The only Rails-ecosystem *library* businesses that reached seven figures solo are open-core with closed paid gems. Every other gem path produced zero product revenue; consulting or acqui-hire was the exit.

### Sidekiq (Mike Perham / Contributed Systems)
- **What / who / when:** Background-job processor for Ruby. Released 2012-02-05; Sidekiq Pro Oct 2012; Sidekiq Enterprise 2015. One-person company for its entire life; no employees.
- **License history:** Core LGPLv3 throughout (never changed). Pro/Enterprise closed, proprietary gems under a commercial licence. Buying Pro also grants a commercial licence for the LGPL core ("avoiding any legal issues your lawyers might raise").
- **Money model over time:**
  - 2012: Pro as a **one-time purchase**. Perham calls this his primary mistake: after ~1.5 years he switched to annual subscriptions because "I'm still putting in features, bug fixes, support, but they're not paying anymore."
  - 2012–2014: side project at ~20 hrs/week for 18 months; Pro went $0 → $10K/mo in 18 months; quit his job summer 2014.
  - 2015: Enterprise priced by **production worker-thread count** (dev/staging free). Pro is flat per organisation, unlimited servers.
  - Distribution: private gem server with credentials. **No DRM, no licence-key checks.** Cancelled subscriptions lose gem-server access; installed gems keep running.
  - Appliance/redistribution licences ($14,995/yr Pro, $39,995/yr Enterprise). Faktory (2017). Since 2025 he sponsors Hanami/dry-rb/rom.
- **Pricing today:** Pro $99/mo ($995/yr); Enterprise "starting at $269/mo" (thread-count tiers; unlimited $79,500/yr; 1 hour/day autoscaling allowance of 2×). Price lock for at least a year for on-time payers; lapsed subs re-buy at current price. Two-week refund window. Credit card only, fully automated.
- **Traction & revenue signals (all claimed by Perham):** May 2017: ~$80K/mo, ~800 customers; 90% of sales from existing users upgrading or bringing it to a new job. May 2023: "closer to $10 million than $1 million," ~2,000 customers. Nov 2023: "$7M" bootstrapped revenue headline. 2025: >2,000 customers, "approaching $10m/year," zero employees. Logos: Adobe, Comcast, Condé Nast, Customer.io, DigitalOcean, Esri, Gusto, Heroku, Kickstarter, Netflix.
- **Inflection points:**
  - The first 5–10 Pro buyers were his ~20 heaviest free users who "had observed his development quality." Trust preceded sales.
  - Subscriptions (2013–14) made revenue predictable and let him quit.
  - Enterprise (2015) added a second, larger price point tied to scale — what took him from ~$1M to ~$10M.
  - Pricing rule: keep Pro **under $1,000/yr** because "anything over a thousand dollars requires a VP sign-off"; spread revenue across many small customers.
  - Feature-split rule: "If 100 percent of people need it, it goes into core Sidekiq." Paid = specialised features that need real support (reliability, batches, rate limiting, encryption, periodic jobs, unique jobs, rolling restarts, historical metrics).
- **Failures / mistakes / backlash:** One-time licensing at launch. Recurring community grumbling that **job reliability** (super_fetch) is paid-only. Never discounts, never sales calls, never hires — deliberately caps the business.
- **Status today (2026):** Sidekiq 8.1.7 (Aug 2026); SF Ruby 2025 talk "Open source, business and the future." No sale, acquisition or succession plan found; intends to support Sidekiq for "10, 20 years."
- **Lessons for RED:**
  - Ship the paid tier only once you have a visible cohort of heavy free users who trust your release quality; instrument (opt-in) who runs RED at scale before launching Server/Enterprise.
  - Price the first paid tier under the manager-approval line (~$1,000/yr), flat per organisation with unlimited environments; scale-based pricing only in the top tier.
  - Do not gate a feature that 100% of users need (capture, grouping, notifications). Gate what large teams need: SSO, audit logs, retention, multi-app rollups, SLAs.
  - Subscription from day one; annual, credit-card, automated. No one-time licences.
- **Sources:** https://www.mikeperham.com/ · https://sidekiq.org/wiki/Commercial-FAQ · https://sidekiq.org/products/enterprise/ · https://www.indiehackers.com/podcast/016-mike-perham-of-sidekiq · https://www.startupsfortherestofus.com/episodes/episode-661-millions-in-revenue-as-a-one-person-software-company · https://saas.group/podcasts/saas-unbound-interview-mike-perham-sidekiq/ · https://garrettdimon.com/starting-and-sustaining/interviews/mike-perham · https://www.indiehackers.com/interview/how-charging-money-for-pro-features-allowed-me-quit-my-job-6e71309457 · https://hanakai.org/blog/2026/03/12/thank-you-sidekiq-2026

### Oban (Elixir; Sorentwo)
- **What / who / when:** Postgres-backed job processor for Elixir (2019). Oban 2.0 + Oban Web + Oban Pro launched 2020-06-12. Small family team (Parker and Shannon Selbert; 2–3 people, unverified).
- **License history:** Core Apache 2.0. Oban Web commercial 2020 → **Apache 2.0 on 2025-01-16**. Oban Pro remains commercial, distributed from a private Hex repo.
- **Money model over time:** Web was "our first foray into building a viable business model"; free trial eliminated in 2020 "due to abuse." Jan 2025: Web subscriptions discontinued; "Only Oban Pro." Pricing (2026): Pro $150/mo or $135/mo annual, **per application** (unlimited nodes); Python port licence; Enterprise custom. Source is viewable, not obfuscated: "distributing a compiled, obfuscated tarball would hinder our troubleshooting and do little to deter stealing... we favor trusting the community, keeping a moving target, and backing it all up with ample support."
- **Traction:** No public revenue. Forum users called Web+Pro "costly" before the change.
- **Inflection points:** Open-sourcing the dashboard to widen the funnel into Pro — the Sidekiq shape: free core + free UI, paid orchestration. Adding Python (2025–26) to expand beyond Elixir.
- **Failures:** Charging for the dashboard for five years was a drag on adoption (their own rationale). Per-application licensing creates friction for agencies/monorepos.
- **Lessons for RED:** The UI/dashboard is the funnel, not the product — keep RED's dashboard free; sell what enterprises do with it. The "trust + moving target + support" stance (no DRM) mirrors Sidekiq and worked in a small ecosystem. Per-organisation is simpler than per-app.
- **Sources:** https://sorentwo.com/2020/06/12/announcing-oban-pro · https://oban.pro/articles/oss-web-and-new-oban · https://oban.pro/pricing · https://elixirforum.com/t/oban-web-to-be-open-sourced/67100 · https://elixirforum.com/t/how-do-things-like-oban-pro-work-in-elixir/63531

### Hangfire (.NET; Sergey Odinokov)
- **What / who / when:** Background jobs for .NET, 2014, solo. "Introducing Hangfire Pro" 2014-11-15. Company moved to Hangfire OÜ, Tallinn, Estonia, founded 2022-03-01.
- **License history:** Core LGPLv3 (dual: LGPL or commercial). Pro/Ace closed, private NuGet feed.
- **Money model:** Open core, **per-organisation, perpetual licence + yearly maintenance** ("regardless the number of developers"): Startup $500/yr (Pro), Business $1,500/yr (Pro + Ace, source access, email support), Enterprise $4,500/yr (royalty-free EULA, priority support, PO/invoice). 30-day unconditional money-back.
- **Traction & revenue signals (Estonian business registry, reported):** revenue €700,877 (2022, partial), €1,133,854 (2023), €1,094,578 (2024), €1,175,204 (2025); net profit €633,970 (2024), €390,871 (2025); **0 employees** on payroll; balance sheet €1.58M (2025).
- **Failures:** Growth plateaued around €1.1M for three years; profit falling. No backlash in the record.
- **Lessons for RED:** A solo maintainer in a mid-size ecosystem can sustain ~€1.1M/yr with perpetual+maintenance pricing and zero staff. "Commercial licence for the copyleft core" is a free revenue line for enterprises whose legal teams dislike LGPL/AGPL — RED is MIT so this lever does not exist unless future modules use a different licence. Money-back guarantee + per-org licensing removes procurement friction.
- **Sources:** https://www.hangfire.io/pricing/ · https://www.inforegister.ee/en/16452321-HANGFIRE-OU/ · https://github.com/HangfireIO/Hangfire/blob/main/LICENSE.md

### Spree Commerce → First Data → Solidus fork → Spark Solutions/Vendo revival
- **What / who / when:** Rails e-commerce engine, 2007, Sean Schofield. Spree Commerce Inc. (VC-backed) 2011–2015; acquired by First Data Sept 2015; Solidus forked 2015 by Stembolt; Spree maintained since 2016 by Spark Solutions/VinSol, now commercially backed by Vendo.
- **License history:**
  - 2007–2024: BSD-3-Clause.
  - **Sept 2024 (v4.10): AGPL-3.0** for new contributions, plus a commercial licence from Vendo for SaaS/multi-tenant redistribution, plus a "Developer Covenant" promising not to enforce AGPL §13 against single-tenant stores.
  - **Apr 2025 (Spree 5.0):** Community Edition (open) + Enterprise Edition (proprietary modules).
  - **Early 2026: core reverted to BSD-3-Clause** "after listening to community feedback... to avoid confusion and remove any barriers to adoption." Multi-Store module remains AGPL-or-commercial; Enterprise modules proprietary.
  - Solidus: BSD-3 throughout.
- **Money model over time:** 2011 $1.5M seed (AOL, True Ventures); Feb 2014 $5M Series A (Thrive); total $6.5M. 2014: pivot toward **Wombat**, a hosted integration platform. 2015: First Data acquisition (terms undisclosed) "to move into open source payments." Wombat shut down 2016-03-31. Original team stopped maintaining the OSS. 2016–: Spark Solutions (Polish agency) took over; consulting revenue. 2024–25: Vendo sells **Enterprise Edition** (multi-vendor marketplace, B2B, multi-tenant, SSO/SAML, audit logs, SLAs) — "a 5 figure investment" annually, positioned "competitively with Shopify Plus." Solidus: **no company**; Open Collective; Nebulab's "several hundred thousand dollars a year worth of development time."
- **Traction:** Spree 15.6K stars, 800+ contributors. No revenue disclosed by Spree Commerce Inc., Vendo, or Nebulab. Super Good Software notes >90% of recent Spree commits come from a single company.
- **Inflection points:**
  - VC + pivot to a hosted product that was not the OSS: community perceived abandonment. Solidus's stated reason: Spree "released a series of minor versions that were unnecessarily difficult to upgrade," and agencies running real stores wanted stability over roadmap.
  - The acquirer had no interest in the OSS; the project went dormant within months.
  - Revival came from agencies whose consulting depends on the engine.
  - The 2024 AGPL move triggered enough confusion that it was reversed in ~15 months; the enterprise-module split (not the core licence) is what stuck.
- **Lessons for RED:**
  - Do not relicense the core to copyleft to force enterprise deals; sell proprietary **modules** around a permissive core. Spree's reversal is the cleanest proof in the Rails world.
  - Upgrade pain is what makes shops fork or leave. For an engine inside host apps, backwards-compatible migrations and versioned upgrade guides are a commercial feature.
  - If you ever sell, the buyer's attitude to the OSS determines whether the community forks.
  - A "5-figure annual" enterprise module sold alongside consulting is the model Vendo settled on; that is the realistic enterprise price band in Rails e-commerce.
- **Sources:** https://en.wikipedia.org/wiki/Spree_Commerce · https://techcrunch.com/2015/09/18/first-data-buys-spree-commerce-to-move-into-open-source-payments-technology/ · https://spreecommerce.org/why-spree-is-changing-its-open-source-license-to-agpl-3-0-and-introducing-a-commercial-license/ · https://spreecommerce.org/spree-commerce-developer-covenant/ · https://spreecommerce.org/what-is-the-price-for-the-spree-enterprise-edition/ · https://supergood.software/solidus-versus-spree/ · https://solidus.io/blog/support-solidus · https://opencollective.com/nebulab

### Discourse
- **What / who / when:** Rails forum platform announced 2013-02-05 (1.0 Aug 2014) by Jeff Atwood, Robin Ward, Sam Saffron. ~79 team members today.
- **License history:** GPLv2+ throughout. One codebase; "There's no super secret special paid commercial version with better or more complete features."
- **Money model over time:** 2013 seed from First Round, Greylock, SV Angel (small, early). Revenue = **managed hosting only** (plus enterprise services, migrations, plugins like Discourse AI). Aug 2021: $20M Series A. Pricing 2026: Pro $100/mo, Business $500/mo, Enterprise custom. Early small communities deliberately subsidised by enterprise accounts.
- **Traction & revenue signals:** May 2017: ~$120K/mo, ~600 hosting customers, "doubling every year" (Indie Hackers, reported). Team 20 (2017) → 44 (2020) → 79 (2026). 3,000+ businesses on official hosting (2022). Logos: GitLab, OpenAI, Docker, Elastic.
- **Inflection points:** Making self-hosting genuinely easy (one-container install) built the install base; hosting monetised the segment that didn't want ops. Leadership transition Feb 2023.
- **Failures:** Slow and capital-light for years (~$1.4M ARR four years in). A pure-hosting model leaves the largest self-hosters paying nothing; Discourse accepts this as marketing.
- **Lessons for RED:**
  - Hosting-only works when the thing is a **standalone app** with ops burden. RED is an engine inside the host app; the customer already has the ops. A Cloud edition must sell something else (aggregation across apps, retention, alerting).
  - "One codebase, no secret paid version" is the strongest trust posture in this cohort, but caps monetisation to hosting/services — the opposite bet from Sidekiq/GitLab.
  - Subsidise small communities/indies loudly; enterprises adopt what their engineers already used elsewhere.
- **Sources:** https://www.indiehackers.com/interview/jeff-atwood-on-growing-discourse-to-120-000-mo-51b47125cf · https://en.wikipedia.org/wiki/Discourse_(software) · https://www.discourse.org/pricing

### GitLab (buyer-based open core → IPO)
- **What / who / when:** Rails DevOps platform, 2011 (Dmitriy Zaporozhets), Sid Sijbrandij joined 2012, incorporated 2014, YC 2015. IPO 2021-10-14 at ~$11B.
- **License history:** CE MIT (2011–). EE proprietary "EE License." CE and EE merged into a single repository with proprietary code under `ee/` (2019, unverified date).
- **Buyer-based open core, precisely (Sijbrandij):** "Buyer-based open core is a framework for determining which features are made to be open source and which are proprietary, based on who cares most about the feature. Features that appeal most to an individual contributor are open source and free. Features that appeal most to management or executives are proprietary and not free." Tiers map to personas (Free = individual contributor; Premium = manager/director; Ultimate = executive); a feature's tier is decided by *who would champion the purchase*, not by technical layering. Stewardship rules: make the open source version really good; **never withhold bug fixes or security fixes** from the free edition; predictable placement model; **do not remove features that were previously open source**.
- **Money model over time:** Open core with self-managed licences + GitLab.com SaaS + GitLab Dedicated (single-tenant SaaS, 2023). Premium ~$29 and Ultimate ~$99 per user per month (unverified current).
- **Traction & revenue signals (SEC/IR, reported):** FY2025 revenue $759.2M (+31%); subscription 87.8% of revenue, self-managed licence 12.2%; SaaS 29% (+36% YoY, driven by Dedicated). Implied **self-managed ≈ 71% of revenue**. FY2026: revenue $955.2M (+26%); crossed $1B ARR; 1,456 customers >$100K, 155 >$1M; NRR 118%; FCF $220M.
- **Inflection points:** Persona-based tiering gave a defensible, explainable rule for what is paid. Self-managed remained the majority of revenue post-IPO.
- **Failures / backlash:** Repeated free-tier tightening (Starter removal, SaaS user caps); 2019 telemetry plan reversed after pushback (unverified); growth decelerating.
- **Lessons for RED:**
  - Adopt the persona rule verbatim: **developer-facing features free** (capture, grouping, dashboard, notifications, i18n); **manager features paid** (team assignment, SLAs, reports across apps, retention policies); **executive/compliance features Enterprise** (SSO/SAML, audit logs, RBAC, data residency, support contracts). Publish the rule.
  - Commit publicly to never withholding bug/security fixes from the free edition and never moving a shipped free feature behind a paywall.
  - Self-managed licences are the majority of GitLab's revenue at $1B scale. RED's Server edition is the main event; Cloud is optional.
- **Sources:** https://about.gitlab.com/blog/2019/04/03/five-ways-resist-service-wrapping-buyer-based-open-core/ (404; excerpt via search) · https://www.linkedin.com/posts/sijbrandij_open-core-is-a-misunderstood-business-model-activity-7085686601355300864-QrtV · https://thenewstack.io/a-standard-pricing-model-for-open-core/ · https://ir.gitlab.com/ (FY2026 results) · https://handbook.gitlab.com/handbook/company/stewardship/

### Chatwoot (Rails; open core + cloud; YC W21)
- **What / who / when:** Customer-support platform. Three founders. Built proprietary 2017 → failed → open-sourced 2019 → YC W21 → $1.6M seed Aug 2021.
- **License history:** MIT except `enterprise/` (separate commercial licence: "You may copy and modify the Software for development and testing purposes, without requiring a subscription"; production use requires one). Founders on HN: "Whatever is MIT now, will stay as MIT." CE/EE built from a single repo (issue #4268, explicitly copying GitLab/PostHog).
- **Money model:** Cloud per agent: Hacker free, Startups $19, Business $39, Enterprise $99/agent/mo. Self-hosted: EE unlocked via a licence key purchased through Stripe from the super-admin panel, tied to an "Installation Identifier," from $19/agent/mo. EE-only: whitelabel, SLA management, audit logs, agent capacity, SAML SSO. Captain AI credits as add-on.
- **Traction:** "1,000+ companies" at HN launch (2021); "15,000+ organizations" (2026 site). GetLatka estimates $870K ARR (2024), 10 staff (est., low confidence).
- **Inflection points:** Open-sourcing a failed proprietary product produced adoption. HN critique: MIT core makes the OSS feel like "a free-trial that appeals to engineers" and invites forks by competitors.
- **Failures:** Revenue modest relative to adoption — the classic open-core conversion gap. Per-agent pricing on self-hosted requires a phone-home licence server, which self-hosters dislike.
- **Lessons for RED:** The `enterprise/` folder in one MIT repo is the standard Rails pattern. A licence key tied to an installation identifier, purchasable self-serve via Stripe from the admin UI, is a proven self-hosted enterprise flow; keep dev/test unlicensed. Adoption ≠ revenue: build the paid tier for the *buyer*, not the installer.
- **Sources:** https://news.ycombinator.com/item?id=26501527 · https://github.com/chatwoot/chatwoot/blob/develop/enterprise/LICENSE · https://github.com/chatwoot/chatwoot/issues/4268 · https://developers.chatwoot.com/self-hosted/enterprise-edition · https://www.chatwoot.com/pricing

### Avo (Adrian Marin; Rails admin framework)
- **What / who / when:** Rails admin/internal-tools framework, late 2020, Adrian Marin (Romania); three co-founders now. TinySeed Spring 2024.
- **License history:** Open-core from the start; "free forever version is open source and includes 70+% of all the features." Paid add-ons as gems with licence-key verification.
- **Money model:** Per app, unlimited users: Community free; Essentials $75/mo; Growth $145/mo; Everything $249/mo; à-la-carte add-ons $15–40/mo; Enterprise custom (audit logging, SSO, RBAC, airgapped, priority support). Took TinySeed "to invest more and take more risks."
- **Traction:** No public revenue or MRR found. Repositioned from "admin panel" to "internal tools/operations framework" (June 2025). Blog posts (2025): "Developer marketing is important," "Two things I wish I knew when I started to build an internal tool framework."
- **Failures:** Adrian's own posts stress that positioning and marketing, not code, were the gaps; pricing moved several times. Friendly.rb conference paused Sep 2025.
- **Lessons for RED:** Avo is the closest analogue (a Rails engine sold per-app with a licence key) and it needed outside money plus a repositioning to grow; budget for marketing. Per-app/unlimited-users pricing fits engines embedded in host apps. "Enterprise = audit logs, SSO, RBAC, airgapped" is the same list across Avo, Chatwoot, Spree EE — the Rails enterprise checklist.
- **Sources:** https://avohq.io/pricing · https://avohq.io/blog/avo-and-tinyseed · https://www.codewithjason.com/podcast/11291339-161-adrian-marin-founder-of-avo-admin/ · https://churnkey.co/subscription-heroes/how-a-self-taught-developer-built-a-saas-business-adrian-marin-founder-ceo-of-avohq/ · https://blog.adrianthedev.com/

### Bullet Train (Andrew Culver) and Jumpstart Pro / GoRails / Hatchbox (Chris Oliver)
- **Bullet Train:** Rails SaaS starter, paid product from 2017 (private repo). Open-sourced under MIT in 2022, funded by ClickFunnels, where Culver is now President; README: "Open-source development sponsored by ClickFunnels." The sponsor wanted the framework maintained and adopted more than it wanted licence revenue; the paid product had capped adoption. Status 2026: maintained, no paid tier.
- **Chris Oliver:** GoRails (2014), Hatchbox (Jan 2017), Jumpstart Pro (~2019). Reported: **$1M cumulative revenue across 6.5 years** by Aug 2020 (GoRails ~50%, Jumpstart ~25%, Hatchbox ~25%); 23,000 email subscribers; Jumpstart moved from one-time ($149/$449) to annual ($249/yr single site, $749/yr unlimited). Hatchbox lowest churn but highest support load; GoRails high churn; Jumpstart easiest to run.
- **Lessons for RED:** Bullet Train shows the *exit* path when a paid Rails product stalls: a sponsor pays for open-sourcing. Chris Oliver's "sell source code as an annual subscription" is a viable ~$250K/yr revenue line; the audience (23K emails) took years to build and drove every launch. RED's ~38K downloads is a list to start capturing now.
- **Sources:** https://bullettrain.co/ · https://github.com/bullet-train-co/bullet_train · https://www.indiehackers.com/product/gorails/1m-in-revenue--MF6J-IzP0vWNyo5MGm9 · https://www.indiehackers.com/podcast/183-chris-oliver-of-gorails · https://jumpstartrails.com/pricing

### 37signals ONCE (Campfire, Writebook, Fizzy)
- **What / who / when:** ONCE announced late 2023 by DHH/Jason Fried as "pay once, own it, self-host" web apps with source included. Campfire early 2024 (~$299, unverified); Writebook July 2024 **free**; Fizzy Dec 2025 under an "O'Saasy" source-available licence then open-sourced; Campfire MIT in 2025. 2026-03-16 "ONCE (Again)": relaunched as an open-source single-machine **app server** (Docker, zero-downtime upgrades, backups, TUI).
- **License history:** ONCE proprietary-with-source (2024) → O'Saasy (Fizzy) → MIT (all three) → open-source app server (2026).
- **Traction & revenue signals (DHH, reported):** "While the investment in Campfire was recouped, that represented the extent of commercial success"; the paid model "wasn't kind of the rocket ship that it needed to be for us to continue in that direction." No unit sales disclosed. Post-open-sourcing: "Tons of people have been running these apps on their own servers, contributing code back."
- **Inflection points:** DHH: "You gotta listen when the market tells you what it wants!" The market did not want to *buy* self-hosted web apps once; it wanted them free and easy to run. The value moved to the installer/app-server.
- **Failures:** The core hypothesis did not scale even with 37signals's brand. Two licence changes in two years.
- **Lessons for RED:**
  - Do not price the self-hosted product as a one-time purchase, and do not expect "self-hosted + source" alone to be the value proposition.
  - What people wanted was *effortless deployment and upgrades*; RED's installer/upgrade path is where self-hosters feel value.
  - Open-sourcing a stalled paid product produces contributions and goodwill quickly; keep that door open if Server underperforms.
- **Sources:** https://world.hey.com/dhh/once-again-3e99f755 · https://dev.37signals.com/once-app-server/ · https://once.com/ · https://github.com/basecamp/once-campfire

### Laravel ecosystem: Otwell's product stack, Spatie's Flare, LaraBug, Telescope
**Laravel (Taylor Otwell)**
- MIT framework (2011). First paid product **Forge** (Laracon NYC 2014): ~1,000 customers and ~$90K ARR within a month (he expected $2–3K/mo); full-time end of 2014. Then Envoyer, Spark, Nova (2018, $99/$299 one-time + renewals), Vapor (2019). Dec 2023: "sold $10 million worth of software... a lot more than $10 million now." Team ~10 at start of 2024.
- **Sept 2024: $57M Series A from Accel** to build Laravel Cloud (2025) and **Nightwatch** (GA 2025-06-16: hosted monitoring incl. **exception tracking, issue assignment, alerting**). Team ~35 by late 2024. Otwell: "we remain committed to open source."
- **Lesson:** The framework author monetising hosted infrastructure while keeping the library free is the Laravel pattern; Nightwatch shows a framework vendor entering error tracking, in direct competition with ecosystem SaaS vendors.

**Flare (Spatie)**
- Laravel/PHP error tracker by Spatie (Antwerp agency, 7 people when Flare started, 11 in 2025). Announced Laracon EU 2019-08-30 together with **Ignition**, the open-source error page that became Laravel's default. Closed hosted SaaS; client packages MIT. Pricing per project: Pro ~€9, Business ~€29/project/mo, Enterprise custom; 10-day trial. No customer or revenue numbers; Freek Van der Herten has said the products' "costs are covered."
- **Oct 2025 "Lessons from the deep end":** performance monitoring planned for summer 2024 took 20 months ("scope creep, underestimating tasks, optimistic planning, losing momentum, perfection paralysis"); client work always won over product work; big infra rewrites (Kubernetes, ClickHouse, OpenTelemetry) delayed shipping. Then Laravel **removed Ignition as the default error page and launched Nightwatch**, so the funnel that fed Flare (Ignition's "share to Flare" button) was cut by the framework itself. Stated response: direct engineer support, EU data protection, deep Laravel integration.
- LaraBug alive (SDK updated May 2026). Telescope and Pulse free; Nightwatch is the paid hosted layer.
- **Lessons for RED:**
  - A framework-specific error tracker can survive next to Sentry as the "made for this framework, by people you know" option, but stays small.
  - Do not depend on a distribution channel you do not control. RED's channel is the gem itself; keep the installer and docs owned.
  - The agency/product split killed Flare's velocity; a solo maintainer should ring-fence the hours the paid product gets.
  - Per-project error-volume tiers with a free tier are the local norm (€9–€29/project). A self-hosted alternative can undercut on volume because the customer pays for storage.
- **Sources:** https://laravel.com/blog/accel-invests-57m-into-laravel · https://laravelpodcast.com/episodes/how-taylor-otwell-came-up-with-products-that-have-earned-him-millions/transcript · https://laravel.com/blog/announcing-laravel-nightwatch · https://freek.dev/1442-flare-an-error-tracker-built-for-laravel-apps · https://flareapp.io/blog/lessons-from-the-deep-end · https://flareapp.io/pricing · https://www.larabug.com/

### Devise / Plataformatec → Nubank
- Plataformatec (São Paulo, 2009; José Valim et al.) created Devise, Simple Form, and incubated Elixir. Revenue was **consulting**. 2020-01-06: acqui-hired by Nubank; Nubank wanted the consulting/agile team, not the OSS. Ruby projects transferred to maintainers (Heartcombo), Elixir to Dashbit.
- **Lesson:** The most-installed Rails auth gem never produced product revenue; it produced consulting deals and an acqui-hire.
- **Sources:** https://blog.plataformatec.com.br/2020/01/important-information-about-our-elixir-and-ruby-open-source-projects/ · https://building.nubank.com/tech-perspectives-behind-nubanks-first-acquisition-deal/

### ankane (Blazer, Ahoy, Searchkick, pgvector)
- Dozens of widely used Rails gems; none has a paid tier or company. Funded by GitHub Sponsors and employer time (Instacart). **Lesson:** "ubiquitous gem, zero monetisation" is the default in Rails — a choice, not a failure — which sets the buyer expectation RED has to price against.

### Redmine → Planio
- Redmine (2006, GPL) never had a company. **Planio** (Berlin, Jan Schulz-Hofen) launched hosted Redmine 2010-01-28, bootstrapped from an agency. Reported: $75K/mo (Dec 2016), ">$1M ARR projected 2016"; GetLatka estimates $1.3M, 14K customers, 5 employees (2024), flat since ~2017.
- **Lesson:** Hosting someone else's GPL app tops out around $1–1.5M with a tiny team and does not compound. A third party can capture the hosting revenue of an OSS project whose maintainers never productised it.
- **Sources:** https://www.redmine.org/boards/1/topics/11029 · https://indiehackers.com/interview/maintaining-a-strong-product-vision-to-bootstrap-to-75-000-mo-bc634054db

### ActiveAdmin / Administrate, Mastodon, Gitorious, Refinery/Locomotive
- **ActiveAdmin** (2010, community): Open Collective, Tidelift, Liberapay; no company. **Administrate** (thoughtbot, 2015): consultancy marketing. Both are the free baseline Avo prices against.
- **Mastodon:** Rails, AGPLv3, non-profit. 2024 annual report: revenue €2.19M (2023: €545K), of which Patreon €248.5K from ~10K small donors, direct US donations $1.58M incl. Jeff Atwood ($100K + $1.5M), Mozilla $100K; costs €774K; team 3 → 6; **<1% of users donate**. Donations scale with a mission and a few large patrons, not with usage.
- **Gitorious:** Rails Git forge, 2008, AGPLv3; free hosted + paid on-premise. 11.7% of Git hosting in 2011 → Powow AS 2013 → GitLab 2015-03-03 → shutdown 2015-06-01. GitLab bought the *user base*. An AGPL forge with on-prem licensing lost to a better-funded, faster-moving open-core competitor.
- **Refinery CMS / Locomotive CMS:** monetised only via agency work; no durable product revenue.
- **Sources:** https://joinmastodon.org/reports/Mastodon%20Annual%20Report%202024.pdf · https://en.wikipedia.org/wiki/Gitorious · https://about.gitlab.com/blog/gitlab-gitorious-free-software/

### Django (brief)
- **Sentry** began 2008 as `django-db-log` at Disqus (covered in Cohort III). **Wagtail** (Torchbox) and **django CMS** (Divio) monetised by the sponsoring agencies. **Saleor**: $2.5M seed 2021, $8M 2024; open source + Saleor Cloud.
- **PostHog** (Django backend, MIT + `ee/`, YC W20): 2023-02-08 it **sunset paid Kubernetes self-hosting** because "our small infrastructure team is spending an outsized amount of time supporting the 3.5% of users" on it; kept a free Docker-Compose "hobby" deploy with no support; pushed everyone else to Cloud. Sacra estimates ~$57.5M ARR (Feb 2026).
- **Lesson:** No Django tool sells a paid self-hosted edition at scale; PostHog abandoned paid self-hosting because support cost exceeded revenue share. If RED sells "Server," scope support tightly (known stacks only).
- **Sources:** https://posthog.com/blog/sunsetting-helm-support-posthog · https://posthog.com/docs/self-host · https://tech.eu/2024/02/06/open-source-ecommerce-platform-saleor-raises-8m/

### Patterns across Cohort II
1. The only Rails-ecosystem *library* businesses that reached seven figures solo are open-core with closed paid gems (Sidekiq ~$10M, Hangfire ~€1.1M, Oban undisclosed). Every other gem path produced zero product revenue.
2. Persona-based feature gating is the shared rule that survived: Perham's "if 100% need it, it's core"; Sijbrandij's IC-free/manager-paid. Everyone who gated something developers need (Oban Web, Spree's copyleft core) reversed it.
3. Pricing conventions: per-organisation or per-app with unlimited users/servers; first paid tier under ~$1,000/yr; scale-based pricing only at the top; annual subscriptions, never one-time (Perham's and Chris Oliver's regret; ONCE's failure). Enterprise SKUs are uniformly SSO/SAML, audit logs, RBAC, retention, airgapped, support SLA, PO/invoice.
4. Self-hosted enterprise is where the money is for platforms people already run (GitLab self-managed ≈ 71%; Sidekiq 100%). Hosting-only (Discourse, Planio) works for standalone apps with real ops burden and grows slowly.
5. Paid self-hosting has a support trap (PostHog's 3.5%; Hatchbox's support load). Scope what "Server" support means before selling it.
6. No DRM in the small-vendor tier (Sidekiq, Oban); licence keys in the VC tier (Chatwoot, GitLab, Avo). Both work.
7. Licence changes to the core are net-negative in this ecosystem: Spree AGPL (reverted), ONCE proprietary-with-source (reverted), Gitorious AGPL (lost). The `enterprise/` folder inside an MIT repo is the accepted pattern.
8. Whoever funds the maintainer sets the roadmap (First Data → Spree dormant; Accel → Ignition removed → Flare's funnel cut; ClickFunnels → Bullet Train freed). Plan paid editions to be self-funding rather than sponsor-funded.

---
<a id="cohort-iii"></a>
## 6. Cohort III — Self-hosted error tracking & observability outside Rails

Nobody in error tracking makes money from the self-hosted install itself except by selling support or SSO around it. And Sentry's own leadership hands every competitor the "self-hosted is second-class" narrative.

### Sentry
- **What / who / when:** Error monitoring that grew into a "developer-first" observability suite. Started 2008 as a 71-line Django plugin by David Cramer (solo); Chris Jennings co-founded the company; SaaS launched 2012. Milin Desai CEO 2019–20; Cramer moved to CPO. ~455 employees (reported, Tracxn).
- **License history:** BSD-3 from 2009. **Business Source License (BSL 1.1)** on 2019-11-06, 36-month conversion to Apache-2.0 — explicitly *not* open core: "anyone should be able to run Sentry for themselves… no feature parity gap." Aug 2023: called BUSL-licensed Codecov "open source," got hammered, apologised. **Functional Source License (FSL)** 2023-11-17: 2-year conversion to Apache-2.0/MIT, fixed "Permitted Purpose" forbidding only competing commercial use. **"Fair Source"** brand launched 2024-08-06 (fair.io). Client SDKs stayed permissive throughout.
- **Money model over time:** 2008–2012 pure OSS, no revenue. 2012 hosted SaaS at **$7/month** — Cramer: "monetize right away, to recognize if it's gonna work or not." Bootstrapped to **$600K ARR, profitable, early 2015** with **~2,000 paying customers before the first round**. Seed $1.5M (2015) … Series E $90M at **$3B valuation, May 2022**, total raised $217M. Revenue ~70% self-serve, 30% enterprise (reported, Sacra). Never sold a paid self-hosted edition; enterprise gets single-tenant *hosted*. Pricing today: Developer free (5K errors), Team $26/mo annual, Business $80/mo annual, Enterprise custom; Aug 2025 plan reshuffle added Logs and raised span pricing.
- **Traction & revenue signals:** ~$99M ARR 2022, **$128M ARR end-2023, 50K customers** (reported, Sacra). Own Aug 2024 post: **100K cloud customers, >$100M revenue, "over 10,000 organizations use Sentry under Fair Source internally"**. Self-hosted opt-in beacon: **18,751 instances seen in 5 years, 3,950 active on recent versions** (May 2024). Cramer earlier: SaaS is "at least five times larger than the open source installation base." External code contributions after relicensing: 3.5% → 3.4% of commits.
- **Inflection points:** (1) Charging from day one of SaaS. (2) Deliberately *not* chasing existing self-hosters: "None of the companies using the early open-source version ever converted to cloud" — they bet on the 10-year long tail: engineers who used self-hosted Sentry at Uber/Airbnb bring it, hosted, to their next job. Cramer turned down an Uber on-prem support renewal to stay pure cloud. (3) "Commoditize the market": a big payments company switched from a competitor to self-hosted Sentry, "didn't pay us a dime, but it took away 10 or 20 percent of that competitor's revenue… less than a year later, they paid us half a million dollars a year." (4) 2020+: expansion from errors into APM, replay, logs at "gym membership" $29. (5) Fair Source stopped the "open-source washing" fights.
- **Failures / mistakes / backlash:** 2019 BSL: HN critics (legal teams can't reason about "competing product"; "Sentry also got work for free from people who assumed the open source project would stay that way"); website still said "open source" for a while. 2023 Codecov "open source" claim — Whitacre: "We sort of stuck our foot in it, stirred the hornet's nest." Jan 2024 ToS change letting Sentry train AI on customer data — reversed 2024-04-12 after backlash. Self-hosting openly de-prioritised: Cramer, Apr 2025: "We enable self-hosting because not everyone can use a cloud service (e.g. government regulation), otherwise we probably wouldn't even spend energy on it… the self-hosting experience is awful today"; docs warn "as Sentry evolves, our self-hosted version will become more complex"; 16 GB RAM minimum; no support for self-hosted. This gap is exactly what GlitchTip, Bugsink and Telebugs sell into.
- **Open Source Pledge:** Sentry paid maintainers $155K (2021), $260K (2022), $500K (2023), $750K (2024), $750K (2025). Launched the Open Source Pledge 2024-10-08 ($2K/dev/year); members had paid $4.5M by Jan 2026.
- **Status today (2026):** Private, >$3B, >$100M ARR, FSL/Fair Source; self-hosted Docker Compose distro maintained but explicitly second-class.
- **Lessons for RED:**
  - Sentry never monetised self-hosting and says it never will — the vacuum is real and durable; RED's Server edition competes with Sentry's *neglect*, not its product.
  - The long-tail funnel took ~10 years and VC patience. A solo maintainer should pair it with something that pays *now*.
  - Relicense *before* you have a community that feels betrayed, or don't; the "still says open source on the site" mismatch was the most-cited sin.
  - Parity between free and paid ("no feature delta") was Sentry's stated principle for a decade; if RED goes open-core it should say so plainly and early.
- **Sources:** https://blog.sentry.io/relicensing-sentry · https://blog.sentry.io/introducing-the-functional-source-license-freedom-without-free-riding/ · https://blog.sentry.io/sentry-is-now-fair-source/ · https://openpath.quest/2024/widespread-use-of-a-fair-source-product/ · https://review.firstround.com/sentrys-path-to-product-market-fit/ · https://www.flagsmith.com/podcast/sentry · https://sacra.com/c/sentry/ · https://blog.sentry.io/another-year-another-750-000-to-open-source-maintainers · https://news.ycombinator.com/item?id=21467299 · https://news.ycombinator.com/item?id=41171665 · https://news.ycombinator.com/item?id=43730831 · https://lucumr.pocoo.org/2023/11/19/cathedral-and-bazaaar-licensing/ · https://github.com/getsentry/self-hosted/issues/2739

### Bugsink
- **What / who / when:** Self-hosted, Sentry-SDK-compatible error tracker in Django. Solo founder Klaas van Schelven, Bugsink B.V. (Utrecht), full-time. Public beta 2024-10-04; 1.0 2024-12-03; 2.0 2025-09-16. Origin: tried to self-host Sentry for a colleague, found it "more trouble than it was worth."
- **License history:** Launched under a custom licence where "production use requires a license" — users found it confusing. **2025-01-15: switched to Polyform Shield** — free for any non-competing use, including commercial production self-hosting; competitors may not fork it.
- **Money model over time:** Phase 1 (2024): paid licence for production self-hosting — abandoned because it confused buyers and slowed adoption. Phase 2 (Jan 2025→): self-hosted free; **hosted Bugsink** (free for individuals, €15/mo for teams); "premium support" priced case-by-case; a paid "self-hosted Sentry support" service; Enterprise Edition (LDAP/SSO, compliance reporting) named as a *future* line. Mar 2026: free hosted tier raised to 15K events/month. He wrote that "the question of monetization is pushed further into the future."
- **Traction & revenue signals:** Show HN Apr 2025: "hundreds" of active installs, ~1M events/day across them (claimed). ~2.0K stars; Docker Hub 100K+ pulls. A single instance handles ~1.5M errors/day on SQLite (claimed). **No revenue or customer counts published.**
- **Inflection points:** Content marketing aimed at Sentry pain: "Why I gave up on self-hosted Sentry" (16 GB RAM, 837 lines of install shell, €15.90/mo Hetzner box vs €3.29) and "Sentry pricing explained"; the HN repost drew a reply from Cramer himself. Technical positioning as product decision: SQLite default, own task queue, server-rendered templates — "runs on a $5 Hetzner box."
- **Failures / backlash:** The initial paid-licence model reversed within ~3 months of 1.0. HN flagged "one-man band" sustainability risk and asked "why not GlitchTip?". Revenue opacity.
- **Status today (2026):** Active, hosted service in EU, solo. The closest analogue to RED one generation later — same shape, one framework over.
- **Lessons for RED:**
  - "Pay for production self-hosting" from a solo dev confused customers and was scrapped inside three months. RED's Server edition needs a much crisper trigger (seat count? SSO? support SLA?) than "production use."
  - Polyform Shield / FSL-style non-compete licences did not stop adoption when chosen before traction; MIT is not required to win self-hosters, but a change *after* adoption is costlier.
  - Attack Sentry's self-hosting story directly and by name; its leadership is handing you the quotes.
  - Publish the operational-cost comparison — it was Bugsink's most-shared content.
- **Sources:** https://www.bugsink.com/blog/new-license-new-pricing/ · https://www.bugsink.com/blog/bugsink-1.0/ · https://www.bugsink.com/blog/why-i-gave-up-on-self-hosted-sentry/ · https://news.ycombinator.com/item?id=43681141 · https://news.ycombinator.com/item?id=43725815 · https://github.com/bugsink/bugsink · https://www.bugsink.com/self-hosted-sentry-support/

### Healthchecks.io
- **What / who / when:** Cron/heartbeat monitoring, Django. Pēteris Caune, Latvia; "a one-man software and consulting company." Launched July 2015 as a side project; his only income since Jan 2022, still described as part-time.
- **License history:** **BSD-3-Clause, unchanged since 2015.** Everything in the hosted service is in the repo; no enterprise edition.
- **Money model:** Hosted SaaS only. Hobbyist $0 (20 checks), Supporter $5, Business $20/mo (100 checks), Business Plus $80/mo (1,000 checks); open-source projects and nonprofits get Business free. Feb 2026: removed team-size limits from all plans because "the single primary reason why users upgrade is running into their account's check limit" — "word-of-mouth marketing is worth more than the profit." Donates 5% of monthly revenue upstream. Deliberately refuses enterprise plumbing (POs, wire transfers, vendor portals).
- **Traction & revenue signals (all primary):** Jul 2024 ("9 years in"): **652 paying customers, $14,043 MRR.** About page, Aug 2026: **1,034 paying accounts, 92,200 free accounts, $22,600 MRR** (~$271K ARR), 75M pings/day, 99.9%+ uptime. 10.3K stars. ~1.6× MRR growth over two years with no marketing spend.
- **Inflection points:** Keeping prices below incumbents; being fully open source is a *feature* of the hosted product — companies self-host for compliance, individuals for hobby, while for most teams "$16/month is cheaper than maintaining it."
- **Failures:** May 2026 SMS-pumping attack added $1,800 to the Twilio bill. About page warns "multi-hour or even multi-day outages are possible" because it is one person.
- **Lessons for RED:**
  - A permissive licence plus a hosted service can produce ~$270K ARR for one person, *if* the product is narrow and the hosted convenience is genuine. It took 11 years, mostly part-time.
  - Price levers should follow what actually causes upgrades. Instrument what RED's self-hosters hit first before designing tiers.
  - He explicitly does not serve enterprise procurement; RED targeting enterprises must decide whether it wants that plumbing.
  - Publishing MRR annually built trust and press for free.
- **Sources:** https://blog.healthchecks.io/2024/07/running-one-man-saas-9-years-in/ · https://healthchecks.io/about/ · https://healthchecks.io/pricing/ · https://blog.healthchecks.io/2026/02/unlimited-team-sizes-for-all/ · https://indiehackers.com/interview/why-i-dont-focus-on-generating-a-quick-profit-160d4f87b6

### GlitchTip
- **What / who / when:** Sentry-SDK-compatible error tracking + uptime; Django + Angular. Built by Burke Software and Consulting (David Burke); 1.0 shipped 2020-07-15.
- **License history:** **MIT** throughout.
- **Money model over time:** Funded by "mostly unrelated contract work." Hosted: Free 1K events, Small $15/mo, Medium $50, Large $250 (BAA available); EU hosting. Apr 2021 added **paid self-hosted support** ($15/user/month) and "enterprise" (custom branding, SSO), because the user base "is largely self-hosted and most are attracted… because we are easy to run and 100% open source."
- **Traction & revenue signals:** Apr 2021 (primary): 258 orgs on hosted, **only 3 paid**. Aug 2026: Docker Hub ~175K pulls/week. **No revenue disclosed.** Still shipping (Feb 2026).
- **Inflection points:** Sentry's BSL move (2019) created the opening; Sentry's self-hosted bloat sustains it. The 2021 sustainability post is the honest inflection: hosted conversion ~1%, so they pivoted to selling support to self-hosters.
- **Failures:** No evidence it has become a standalone business six years in; still a consultancy side product.
- **Lessons for RED:**
  - MIT + "easy to run" wins installs but almost nobody pays for hosted when self-hosting is that easy; GlitchTip's own fix was paid support for self-hosters — RED's Server-edition thesis.
  - Being consultancy-subsidised removes urgency. Set a deadline for the business to pay for itself.
- **Sources:** https://glitchtip.com/blog/2021-04-09-sustainable-open-source/ · https://glitchtip.com/pricing/ · https://hub.docker.com/r/glitchtip/glitchtip

### Exceptionless and elmah.io (.NET)
- **Exceptionless:** .NET/JS error and log reporting on Elasticsearch, by CodeSmith Tools (started 2012). Closed SaaS 2012–14; **open-sourced 2014-02-18 under Apache-2.0**. Hosted tiers $15–$499/mo; self-hosting free "if you have the resources." ~2.5K stars; still shipping. No numbers. Alive, niche, subsidised by a small company. **Lesson:** a framework-specific Apache tracker with a hosted upsell can survive a decade on a small company's balance sheet — but "survive" is the ceiling; requiring Elasticsearch is a tax RED avoids.
- **elmah.io:** Bootstrapped .NET error-logging SaaS, Aarhus, from Aug 2013. Proprietary, cloud-only, **no self-hosted option**. Plans $26 / $44 / $89 / $269. No numbers. **Lesson:** the bootstrapped closed path works in .NET where self-hosting culture is weaker; in Rails closed-only would forfeit RED's whole positioning. The $26 entry price matches Sentry's Team tier — the market has anchored on ~$25–30/mo.
- **Sources:** https://exceptionless.com/fork-us-exceptionless-goes-open-source/ · https://github.com/exceptionless/Exceptionless · https://elmah.io/about/ · https://elmah.io/pricing/

### Uptime Kuma
- Self-hosted uptime monitor; Louis Lam (Hong Kong), solo, since 2021; MIT. Donations only. **90.7K stars, 8.3K forks** — the most-starred project in this cohort. Open Collective: **$5,715 total raised ever, ~$136/month budget**. No hosted service, no paid edition, no commercial plans found.
- **Lesson:** Stars and donations are uncorrelated with income. If RED wants revenue, build the paid tier *into* the product before the community norm becomes "it's free"; retrofitting a paid edition onto a 90K-star MIT project is nearly impossible politically.
- **Sources:** https://github.com/louislam/uptime-kuma · https://opencollective.com/uptime-kuma

### Highlight.io
- Open-source session replay + errors + logs + traces; YC W23; **$8M seed Aug 2023**. Apache-2.0 with separate licences for `enterprise/`. **Acquired by LaunchDarkly, Apr 2025.** Promise: "remain open source in its current state… the repo will still be there." Aug 2026: repo shows commits, no archive notice; but the blog redirects to launchdarkly.com, the Python SDK is published from LaunchDarkly's org, the docs repo was archived in 2023. Alive as a source dump and SDK base, not as an independent roadmap.
- **Lesson:** VC-backed open-core observability's exit is "get absorbed by a platform"; the self-hosted community is left with a repo whose roadmap belongs to the acquirer. For RED's enterprise buyers, "solo maintainer" is a risk — but so is "will be acquired and sunset"; a permissive core licence is the honest mitigation either way.
- **Sources:** https://launchdarkly.com/blog/welcome-highlight-to-launchdarkly/ · https://github.com/highlight/highlight

### SigNoz / Uptrace / OpenObserve / HyperDX — the OTel-native wave
- **SigNoz** — YC W21; $6.5M seed Sep 2023. MIT core + `ee/`. SigNoz Cloud from $49/mo; Enterprise from **$4,000/mo** in three flavours — dedicated cloud, BYOC, or **self-hosted with a support contract**. ~24K stars. Repeatedly fields "is SigNoz really open source?" threads.
- **Uptrace** — started under BSL, now AGPL-3.0 (the reverse of the usual direction). Cloud plus "self-hosted/on-prem with licensing… contact sales."
- **OpenObserve** — Rust. **Apache-2.0 → AGPL-3.0 in Nov 2023**: "open source projects are able to capture 1–5% of the value they create… permissive licenses hindered [Elastic and HashiCorp's] ability to capture value." Enterprise features free self-hosted up to 50 GB/day. $10M Series A Apr 2026; "8,000 organizations in production" (claimed).
- **HyperDX** — MIT; **acquired by ClickHouse 2025-03-13**.
- **Pattern:** every OTel-native player raised money, ships a ClickHouse backend, and sells either a cloud or a *supported* self-hosted enterprise tier; two of four exited to a database vendor or platform within ~3 years. The only durable self-hosted revenue line any describe is "self-hosted + support contract + SSO/RBAC gate."
- **Lessons for RED:** The enterprise self-hosted SKU that sells in 2026 is "same software + support contract + SSO/RBAC/audit" — not a fatter feature set. AGPL is being adopted *as a monetisation tool* without measurable adoption harm.
- **Sources:** https://www.signalfire.com/blog/signoz-pioneers-open-source-observability-with-65m-led-by-signalfire · https://signoz.io/enterprise-self-hosted/ · https://github.com/SigNoz/signoz/discussions/4231 · https://uptrace.dev/pricing · https://openobserve.ai/blog/what-are-apache-gpl-and-agpl-licenses-and-why-openobserve-moved-from-apache-to-agpl/ · https://clickhouse.com/blog/clickhouse-acquires-hyperdx-the-future-of-open-source-observability

### Grafana Labs (and Prometheus)
- **What / who / when:** Grafana started 2014 (Torkel Ödegaard, forked from Kibana 3); Grafana Labs founded 2014. LGTM stack + Grafana Cloud.
- **License history:** Apache-2.0 → **AGPLv3 on 2021-04-20** for Grafana, Loki, Tempo. Reasoning: balance "value creation" with "value capture"; *rejected* SSPL because AGPL "is still OSI-approved open source." Commercial features in separate Enterprise builds.
- **Money model:** VC ($663M raised through 2024); Grafana Cloud (free tier, usage-based) and Grafana Enterprise Stack (paid self-managed with enterprise plugins, SSO, RBAC, support).
- **Traction & revenue signals:** ~$270M ARR at $6B valuation (Aug 2024); **>$400M ARR and 7,000 customers (2025-09-30, press release)**; $605M ARR 2026, 20M users, ~1% monetisation rate (est., Sacra).
- **Inflection points:** Cloud free tier (2020) turned self-hosters into signups; AGPL removed the "AWS hosts our software" fear without leaving OSI. Enterprise self-managed is a real revenue line — the one clear proof in this cohort that paid self-hosted works, at the cost of a large sales org.
- **Failures:** AGPL move drew grumbling but no fork of note. The 1% monetisation rate is the sobering number.
- **Prometheus (no company):** Apache-2.0, CNCF. Monetised by others: Grafana Labs (Mimir/Cloud), Chronosphere, PromLabs (Julius Volz), Robust Perception.
- **Lessons for RED:**
  - Paid self-managed works at Grafana — but the buyer is buying SSO/RBAC/support/indemnity, and it took a 1,000+ person company to sell it. RED's Server edition should be designed to be sold by one person: self-serve licence key, no procurement theatre.
  - Expect ~1% of users to pay even with a superb product.
  - MIT → AGPL is a smaller trust hit than MIT → BSL; still a change RED's positioning would have to justify.
- **Sources:** https://grafana.com/blog/grafana-loki-tempo-relicensing-to-agplv3/ · https://grafana.com/press/2025/09/30/grafana-labs-surpasses-400m-arr-and-7000-customers-gains-new-investors-to-accelerate-global-expansion/ · https://sacra.com/c/grafana-labs/ · https://grafana.com/licensing/

### Opbeat → Elastic APM
- Copenhagen, 2013; Django/Node/JS APM; SaaS-only; ~$2.8M raised; 15 staff. **Acquired by Elastic, mid-2017, for $9.5M** (reported). All 15 joined Elastic to build "Elastic APM," explicitly to add an *on-prem* version inside the Elastic Stack. Opbeat brand disappeared.
- **Lesson:** A small, SaaS-only APM with a loyal Django niche was worth ~$9.5M to a platform that wanted the *on-prem* capability. Pure-SaaS niche APMs for one ecosystem tend to end as a feature of something bigger.
- **Sources:** https://techcrunch.com/2017/06/22/elastic-enters-apm-space-with-opbeat-acquisition/

### SaaS vendors selling on-prem editions: did anyone succeed?
- **Rollbar:** Sold "Rollbar On-Premises," then wrote (2017-04-26) that maintaining it "is difficult… and a huge pain for customers, too," and replaced it with HIPAA/ISO-compliant SaaS.
- **Bugsnag / SmartBear:** Still sells an on-premise edition (enterprise-only, clustered) — the one SaaS error tracker with a surviving paid on-prem SKU, sales-led.
- **Sentry:** never sold on-prem; single-tenant hosted instead.
- **Raygun, Airbrake, New Relic, Datadog:** no on-prem product.
- **Takeaway for RED:** Cloud-native vendors that bolted on on-prem mostly retreated or kept it as an enterprise-only, sales-led SKU. Vendors born self-hosted (Grafana, Elastic, SigNoz) keep on-prem as a core revenue line. RED is born self-hosted; Server is the natural line, Cloud the bolt-on — the reverse of Rollbar.
- **Sources:** https://rollbar.com/blog/introducing-compliant-saas-error-monitoring/ · https://docs.bugsnag.com/on-premise/

### Dead or dormant self-hosted trackers, and one pivot
- **Exceptional (exceptional.io):** acquired by Rackspace 2013-03-28; brand dissolved. Hosted trackers get bought for their dev-tool distribution and then dissolved.
- **Cabot (Arachnys):** Self-hosted "lightweight PagerDuty." MIT, 5.7K stars, README: "stable and used by hundreds of companies… but not actively maintained. We would like to hand over maintenance." Corporate side project with no revenue line.
- **Telebugs (Kyrylo Silin, Ruby):** Feb 2024 idea → Aug 2024 hosted SaaS with Telegram alerts — "flopped" (no vision, no audience, "customers hesitated trusting an indie dev with SaaS data"; over-engineered with ClickHouse + NATS). Pivoted Jan 2025; **2025-04-30 shipped Telebugs 1.0 as $299 pay-once, source-included, self-hosted** (Once.com model), rebuilt on vanilla Rails + Docker; free 1.x updates, paid majors. Sales numbers not public. Directly relevant: a solo Ruby dev found buyers distrusted his *hosted* offering and trusted his *self-hosted, pay-once* one.
- **Sources:** https://github.com/arachnys/cabot · https://kyrylo.org/software/2025/05/01/how-the-pay-once-business-model-saved-my-aas.html · https://telebugs.com/

### Patterns across Cohort III
1. Nobody in error tracking makes money from the self-hosted install itself except by selling support or SSO around it. The only pure "pay for the self-hosted bits" case is Telebugs' $299 pay-once — with no public numbers.
2. Conversion from free self-host to paid is ~1–2% at best (Grafana ~1%; GlitchTip 3 of 258; Sentry SaaS "5×" the OSS base after a decade). With ~38K downloads, expect low hundreds of payers.
3. Solo/bootstrapped sustainability came from a narrow product plus hosted convenience, on a permissive licence, over 9–11 years (Healthchecks $22.6K MRR). The solos who monetise fastest sold the *service*, not the code.
4. Licence changes are survivable but always cost trust; direction and timing matter. MIT/Apache → AGPL provoked little lasting damage; BSD → BSL generated years of fights, mostly because marketing lagged the licence. Nobody retrofitted a paid tier onto a 90K-star MIT project.
5. Sentry's leadership hands the "self-hosted is a second-class citizen" narrative to competitors. RED's in-app, no-extra-infra design is the strongest possible version of that pitch.
6. The 2026 enterprise self-hosted SKU is standardised: same binary + support contract + SSO/SAML/SCIM + RBAC/audit log + BAA/compliance story.
7. Cloud-native SaaS vendors retreat from on-prem (Rollbar), self-hosted-native vendors keep it as core revenue (Grafana, Elastic). Hosting a Cloud edition as a solo maintainer replicates Telebugs' failed step; consider selling hosting through a partner (Elestio/DanubeData list GlitchTip and Bugsink) before running it yourself.
8. Open-core observability with VC exits into a platform within ~3 years (Opbeat, Highlight, HyperDX), and the self-hosted community keeps a repo with someone else's roadmap. RED's honest counter-argument: an MIT core with a permanent escape hatch and no acquirer to answer to.

---
<a id="cohort-iv"></a>
## 7. Cohort IV — Solo and tiny-team monetisers ("people like you")

Every durable solo income in this cohort came from a priced product with a distinct buyer — a hosted tier, a licence key for the team build, retainers, or gated education. Sponsorship and partners were accelerants on top, never the base.

### A. Hosted-tier businesses on top of a self-hostable core

#### Plausible Analytics
- **What / who / when:** Privacy-first web analytics. Uku Täht solo from 2018/19; Marko Saric joined as marketing co-founder March 2020; team of 4 by Feb 2022, "8 core members plus paid external contributors" by Feb 2024. No investors, no paid ads.
- **License history:** MIT (Sept 2019, "to build trust in the privacy-first market") → AGPLv3 (Oct 2020, because "corporations [were] happy to take advantage") → 2024-02-23: self-hosted build rebranded **Plausible Community Edition**, trademarks registered, CLA required, business/enterprise features (funnels, ecommerce revenue, Sites API) carved out.
- **Money model over time:** Paid cloud subscriptions from May 2019. Self-hosting free but deliberately de-prioritised: CE gets releases **twice a year**, community-only support, no premium features.
- **Traction & revenue signals (verified from founder posts):** May 2019 $64 MRR → Feb 2020 $403 → Jan 2021 $11,303 → Oct 2021 $42,624 → **2022-06-02: $83,637 MRR ($1M ARR)**. Stopped publishing monthly MRR after 2022. Feb 2024: "12,000+ subscribers." May 2026: "more than 15,000 paying subscribers"; April 2026 "our best month ever" with **1,156 new paying subscribers**. **Self-hosters donate ~$300/month total** (Feb 2024).
- **Inflection points:** Marko's content marketing ("Google Analytics alternatives") and GDPR/UA-shutdown tailwinds; going AGPL in Oct 2020 without losing growth; the 2024 CE split, triggered by resellers "using the Plausible brand while running competing analytics tools." Hosted is the *entire* business.
- **Failures / backlash:** MIT for the first year was later regretted. The CE announcement drew "bait and switch" grumbling but no measurable churn.
- **Lessons for RED:**
  - The $300/mo donation figure is the single most important number in this cohort: a hugely popular self-hosted tool yields nothing from self-hosters unless a paid edition exists.
  - The "slow lane" for self-hosters (twice-yearly releases, no premium support) is a lower-conflict lever than removing features.
  - Register the trademark and write a reseller/brand policy *before* clones appear.
  - The licence flip MIT→AGPL cost nothing measurable at ~$500 MRR. The cheapest time to restrict anything is now.
- **Sources:** https://plausible.io/blog/open-source-saas · https://plausible.io/blog/community-edition · https://plausible.io/blog/homepage-edits-conversion-lift · https://www.indiehackers.com/post/scaling-plausible-analytics-from-400-mrr-to-500-000-arr-in-1-5-years-as-a-1-person-marketing-team-without-any-paid-marketing-w-marko-saric-42e2dde7ff

#### Coolify
- **What / who / when:** Self-hosted Heroku/Netlify alternative. Andras Bacsai (Hungary), started 2021, quit his job July 2022; solo until mid-2024. No outside funding.
- **License:** Apache-2.0; explicit "no paywalled features."
- **Money model over time:** 2021–2023 donations only. 2024: **Coolify Cloud** — a hosted *control plane* (you bring your own servers). Organisational sponsors with logo placement.
- **Traction & revenue signals:** Feb 2025 (Andras on X): gross **$15,700/mo** (Cloud ~$10.5K + donations ~$5.2K), net before tax $12,900; "my last 9-5 job paid $1,700/m." Aug 2026 (Open Collective page): hosted **~€15K+/mo**, GitHub Sponsors ~€4.5K/mo, Open Collective ~€1.2K/mo; **3,000+ cloud users**. 312 current sponsors, 746 past. Indie Hackers still shows a stale "$390/mo" — third-party revenue pages are unreliable.
- **Inflection points:** Heroku's free-tier removal (2022) and the v4 rewrite drove stars past 40K; the Cloud product doubled income within ~12 months without touching the free product. Sponsorship alone plateaued around $5K/mo and only became meaningful in the top ~0.1% of GitHub by stars.
- **Lessons for RED:**
  - Coolify's cloud is "hosting the annoying part" (control plane), not "hosting the data." RED's analogue: a hosted dashboard/fleet view with the customer's Rails app still self-hosted.
  - ~$5K/mo in donations required ~45K stars and 1,000+ lifetime sponsors. At 90 stars, skip straight to a product.
  - Publishing income monthly was itself a growth channel.
- **Sources:** https://x.com/heyandras/status/1901894087604916396 · https://opencollective.com/coollabsio · https://github.com/sponsors/coollabsio

#### Umami, Fider, Miniflux, Rallly, Listmonk, Dokku, Shlink
- **Umami:** Mike Cao, solo 2020 at Adobe; **$1.5M pre-seed led by Race Capital, 2022-07-19**. MIT throughout. Free self-host + Umami Cloud. No public revenue. **Lesson:** MIT + generous free cloud is the *hardest* version of this model; every other case either restricted the licence or kept the hosted tier stingy.
- **Fider:** Guilherme Oenning, solo, AGPLv3 from the start; hosted plans. "~$1,000/month for three years" before selling in 2024 because it "was taking up too much mental space" (reported). His next products are closed-source. **Lesson:** a solo, AGPL, hosted "open alternative" with no marketing engine converges on ~$1K/mo. The difference from Plausible was a second person doing content full-time.
- **Miniflux:** Frédéric Guillot, solo since 2013, Apache. Hosted at **$15/year**, "same code as open source, no lock-in." **Lesson:** works as lifestyle income only when ops cost per tenant is near zero; error ingest is heavier than RSS polling.
- **Rallly:** Luke Vella, solo, AGPLv3. Hosted Pro $5/mo. **2025-05-14 (discussion #1714):** proposed paid self-hosted licences because "it's difficult to prioritize work on self-hosted instances because they don't generate any revenue." Shipped: personal single-user free; **Plus (≤5 users) $49; Organization (≤50 users) $299; Enterprise from $999**; perpetual per major version; own licensing API to address privacy objections. Backlash: "disproportionate vs Home Assistant $65/yr," nonprofit affordability, licence-server privacy, AGPL-contributor fairness. **Lesson:** the closest live template for RED's Server edition; expect the *exact* objections Rallly got; pre-empt with a nonprofit tier and a licence check that phones home minimally.
- **Listmonk:** AGPL, by Kailash Nadh (Zerodha's CTO); Zerodha funds it; no paid edition. Zerodha's **FLOSS/fund (2024-10-15): $1M/yr, grants $10K–$100K**, application via a `funding.json` manifest. **Lesson:** a channel RED can *apply to* — more than any donation channel will yield at RED's size. And: the best "enterprise" anchor for a self-hosted tool is one company that runs it in production and pays you to keep it alive.
- **Dokku / Dokku Pro:** MIT, 25K+ stars, essentially solo for a decade. Donations: Open Collective **$87,013 total**, ~$10.2K/yr run-rate. **Dokku Pro: $849 one-time, lifetime, 1 production + 2 pre-production servers, explicitly "AS-IS, without any support,"** no refunds. **Lesson:** a 25K-star infra project gets ~$10K/yr in donations — the ceiling of the donation channel for *very* popular tools. Pay for the management UI, not the runtime; the "no support" clause is a solo-maintainer survival mechanism.
- **Shlink:** MIT, since 2016, "in his spare time," donations only, no hosted or paid tier. The control case: popular, well-maintained, nine years old, zero business — because no priced offer was ever made.
- **Sources:** https://finance.yahoo.com/news/umami-raises-1-5-million-121300406.html · https://blog.acquire.com/startup-acquisition-episode-111/ · https://miniflux.app/hosting.html · https://github.com/lukevella/rallly/discussions/1714 · https://support.rallly.co/self-hosting/licensing · https://floss.fund/blog/announcing-floss-fund/ · https://pro.dokku.com/ · https://opencollective.com/dokku · https://shlink.io/

### B. Sponsorship-, retainer- and partner-funded maintainers

#### Caleb Porzio (Livewire / Alpine.js) — sponsorware
- **What / who / when:** Solo. Left a ~$90K job 2019-01-11; started Livewire days later; Alpine.js ~a year later. GitHub Sponsors from 2019-12-12. MIT for both (a decision he says he now regrets in principle).
- **Money model over time (from his posts):** Dec 2019–Feb 2020 goodwill sponsors → $573/mo from 23 sponsors. **Feb 2020 sponsorware:** the "Sushi" package released only to sponsors until 75 sponsors, then open-sourced. Two days → **$1,560/mo from 75+ sponsors**. Mid-2020 screencasts: free basics, advanced Livewire screencasts gated behind a **$14/mo** tier → **+$80K in ~90 days; $112,680/yr by June 2020**. Corporate logo tiers ($500/mo) and later paid products (Flux UI, 2024).
- **Traction & revenue signals:** **$1M cumulative on GitHub Sponsors by Aug 2024**: screencasts $725K, corporate logos $200K, consulting $25K, Sushi early access $20K, conference $20K (zero profit), stickers $5K, goodwill $5K. Lost ~$4K/mo ($50K/yr) overnight when GitHub dropped PayPal sponsorships (Jan 2023) with one month's notice.
- **Inflection points:** The screencast tier, not sponsorware, made the income. Docs traffic is "my most valuable asset." Email list > social followers.
- **Failures / warnings:** Payment-platform risk (now Stripe, Paddle, Gumroad, Lemon Squeezy in parallel). GitHub Issues "let random people demand your attention." "There aren't that many" generous people relative to users; sponsorware needs "a constant stream of new ideas." Predicted in 2024 that AI assistants would cannibalise docs traffic — which is exactly what hit Tailwind.
- **Lessons for RED:**
  - Sponsorware works as a *launch spike*, not an income. The durable part was education gated behind a low monthly tier — but only with an audience first.
  - His $11K sponsorware jump required ~20K Twitter followers and a Laravel-community reputation. At 90 stars, build the list first (docs email capture), monetise second.
  - Never depend on one payment rail.
- **Sources:** https://calebporzio.com/sponsorware · https://calebporzio.com/i-just-hit-dollar-100000yr-on-github-sponsors-heres-how-i-did-it · https://calebporzio.com/i-just-cracked-1-million-on-github-sponsors-heres-my-playbook

#### Tailwind Labs (Adam Wathan)
- **What / who / when:** Tailwind CSS v0.1.0 2017-11-01 (MIT). Adam Wathan + Steve Schoger, ~5 people by 2020, ~7–8 by 2025. Paid products *adjacent* to the free framework: Refactoring UI (Dec 2018; "over $2.5M" lifetime), **Tailwind UI (2020-02-26): ~$2M in its first 5 months**; ">$4M total in under 2 years" (Aug 2020, verified); "reliably mid-seven figures per year" (2021). Discovery funnel = docs traffic → paid components.
- **2026-01-06/07 (GitHub PR #2388 comments, verified):** "Traffic to our docs is down about 40% from early 2023 despite Tailwind being more popular than ever… our revenue is down close to 80%"; "75% of the people on our engineering team lost their jobs"; ~6 months of runway; "I feel like a fucking idiot for somehow being able to build this CSS framework that's taken over the world… but I can't figure out how to have it make enough money." LLMs generate Tailwind without visiting tailwindcss.com. Aftermath: Gumroad, Vercel and Google sponsorship commitments (reported).
- **Failures:** Lifetime-license pricing for Tailwind UI meant no recurring base. Single-funnel dependency on docs pageviews.
- **Lessons for RED:**
  - Do not build the business on a *documentation-traffic* funnel. RED's users discover it via RubyGems/README and increasingly via AI assistants that never load the docs. Put the upsell *inside the product* (dashboard banner, upgrade task, licence-key prompt).
  - Prefer recurring (annual licence/support) to lifetime pricing.
  - Adjacent products work at Tailwind's scale, not at 40K downloads; RED's paid line must be *the tool itself* in enterprise form.
- **Sources:** https://github.com/tailwindlabs/tailwindcss.com/pull/2388 · https://adamwathan.me/tailwindcss-from-side-project-byproduct-to-multi-mullion-dollar-business/ · https://devclass.com/2026/01/08/tailwind-labs-lays-off-75-percent-of-its-engineers-thanks-to-brutal-impact-of-ai/

#### Evan You, Tanner Linsley, Daniel Stenberg, Filippo Valsorda, Sindre Sorhus, Louis Lam, small datapoints
- **Evan You (Vue → VoidZero → Cloudflare):** Vue sustained ~a decade on sponsorship. **2024-10-01: VoidZero Inc., $4.6M seed led by Accel** because a unified toolchain "requires a full-time, dedicated team — something that wasn't possible under the independent sustainability model." **2026-06-04: VoidZero joined Cloudflare**; $1M Vite ecosystem fund. **Lesson:** even the most successful sponsor-funded solo maintainer concluded sponsorship caps at "one person's salary." The boundary of the model, not a plan.
- **Tanner Linsley (TanStack):** Full-time ~2023 funded by savings; by 2025 **14–16 partners** (Cloudflare, Railway, Netlify, Clerk, WorkOS, Sentry…) cover "a reasonable salary," a rainy-day fund, and monthly sponsorships for ~12 core contributors. 4B+ downloads, 112K stars, 3M annual site users. **Lesson:** partners buy *audience placement*; not applicable at 90 stars, but the Gold/Silver/Bronze tiering is cheap once RED has a few thousand monthly docs visitors — Rails hosting, DB and APM vendors are natural buyers.
- **Daniel Stenberg (curl):** Since Feb 2019 wolfSSL employs him; companies sign curl support contracts with wolfSSL. 2019 tiers reported: Basic $2,000/yr, Standard $6,000/yr, Premium $23,000/yr, 24×7 $50,000/yr. **Nov 2024: "Rock-solid curl"** — 5-year LTS releases available *only* to support customers. Open Collective **$423,630 total**, ~$90K/yr. **Lesson:** enterprise buyers pay for *guarantees* (LTS, SLA, named engineer), not code. "RED LTS + security backports for customers only" is a clean enterprise product. Piggybacking on an existing vendor's sales/legal is how a one-person project sells $23K contracts to procurement.
- **Filippo Valsorda:** Left Google May 2022; by Feb 2023 **six retainer clients** paying "equivalent to my Google total compensation." July 2024: **Geomys**, a maintainer firm (3 associate maintainers); one fixed monthly retainer per client; 8 named clients (Latacora, Teleport, Tailscale, …). **Lesson:** retainers sell *access and planning input* to companies whose product depends on your code. RED's version: a "design partner" tier for Rails shops — quarterly roadmap calls, private issue channel, guaranteed response — priced in the thousands per year, sold to 3–6 companies.
- **Sindre Sorhus:** 1,100+ npm packages, ~2B downloads/month. Open Collective **$122,969 total since 2019, ~$7.3K/yr**; GitHub Sponsors reported >$10K/mo in 2021 (unverified). **Lesson:** even at 2B downloads/month, donation income lands in the low six figures at best. Per-download yield is essentially zero; Ruby's audience is ~50× smaller.
- **Louis Lam (Uptime Kuma):** 90.7K stars; GitHub Sponsors 39 current / 354 past; Open Collective $5,715 total. No paid product.
- **azu:** **$12,799 for all of 2022** on GitHub Sponsors. **Alex Ellis / OpenFaaS (30K stars):** "~$500/mo, from one end-user company" in 2020, "not even 10% of what I need"; pivoted to **OpenFaaS CE with a 60-day commercial-use limit, Standard $1,250/mo, Enterprise custom** plus consulting. **Lesson:** sponsors at $500–$1,000/mo is where *well-known* mid-size projects sit; a hard commercial-use clause turned it into a business.
- **Sources:** https://voidzero.dev/posts/announcing-voidzero-inc · https://voidzero.dev/posts/voidzero-joins-cloudflare · https://tanstack.com/blog/tanstack-2-years · https://tanstack.com/partners · https://daniel.haxx.se/blog/2024/11/07/rock-solid-curl/ · https://opencollective.com/curl · https://words.filippo.io/full-time-maintainer/ · https://words.filippo.io/geomys/ · https://opencollective.com/sindresorhus · https://github.com/sponsors/louislam · https://dev.to/azu/my-github-sponsors-revenue-2022-38ab · https://blog.alexellis.io/still-in-the-game-my-2020-year-in-review/ · https://www.openfaas.com/pricing/

### C. Larger "open startup" comparators (brief)
- **Ghost:** 2013 Kickstarter $300K; non-profit foundation, MIT; "$750K ARR" March 2017; live dashboard now: **ARR $11,055,673, MRR $921,306, 30,557 customers, net churn 2.92%, ~40 staff**. Revenue entirely Ghost(Pro) hosting; self-hosting free and unrestricted. **Lesson:** hosting-only + transparency page is a 12-year, no-VC path to $11M — but it took a team and a consumer-sized market. Copy the public revenue page, not the market.
- **Bitwarden:** Kyle Spearrin, solo start 2016; server AGPLv3, enterprise features in a `bitwarden_license` directory; $100M growth round from PSG Sept 2022 (reported). **Oct 2024:** desktop 2024.10.0 pulled in `sdk-internal` with a clause forbidding use "with software other than Bitwarden"; GitHub issue "Desktop version 2024.10.0 is no longer free software"; Bitwarden called it a packaging bug and within days re-licensed the SDK under GPLv3. **Lesson:** the single-repo "open core + `/license` folder" layout is standard, but any *transitive* licence restriction that leaks into the free build detonates trust within hours; Bitwarden survived only by reverting fast.
- **Cal.com / Documenso / Formbricks / Typebot:** Cal.com AGPL + `/ee`, VC-funded; GetLatka *estimates* $5.1M ARR (est. only). **Documenso** (2–3 founders, AGPL, pre-seed Aug 2023): **34,000+ users, 340+ paying customers, 10K stars** by end-2025; "enterprise self-host options" launched Sept 2025 (SSO, whitelabel, compliance). **Typebot** (Baptiste Arnaud, solo, AGPL): $300 MRR after year one → **$960 MRR by June 2022** four months after open-sourcing v2.0 — a clean solo datapoint that open-sourcing *increased* paid conversion. **Lesson:** ~340 paying customers after ~2.5 years with a funded 2–3 person team in a hot category is what "good" looks like for open-core B2B; a solo Rails-niche tool should plan for a fraction of that.
- **Sources:** https://ghost.org/about/ · https://chartmogul.com/blog/ghost-chartmogul-dashboard/ · https://www.theregister.com/2024/11/04/bitwarden-switches-password-manager-and-sdk-to-gpl3/ · https://documenso.com/blog/2025-a-year-in-review · https://www.indiehackers.com/post/skyrocket-your-mrr-by-going-open-source-a8c242904f

### D. Failures and post-mortems

#### core-js (Denis Pushkarev) — "9 billion downloads, $400/month"
- ES polyfill used by ~52–80% of top sites, 250M downloads/month, one maintainer in Russia. Money timeline (his 2023-02-14 post): first fundraising **$57/mo**; after core-js@3 (2019) ~$2,500/mo, decaying to ~$1,700/mo; by 2023 **~$400/mo** ("$2 per hour" at 250 h/month) after Tidelift withheld payments over sanctions and Bower's contribution ended. Open Collective lifetime **$194,038; ~$25K/yr** current.
- What he tried: a `postinstall` plea for money/jobs (2019) → "continuous stream of hate… hundreds of messages… every day"; npm 7 then suppressed postinstall output; GitHub Sponsors and PayPal unavailable in Russia. Still maintained; still underfunded (2025).
- **Lessons for RED:** Ubiquity without an *offer* yields nothing; an unsolicited nag in the install path is the worst possible offer. Every channel he had was a *platform* someone else could turn off. Charge through your own Stripe account, own the customer list.
- **Sources:** https://github.com/zloirock/core-js/blob/master/docs/2023-02-14-so-whats-next.md · https://opencollective.com/core-js

#### faker.js / colors.js (Marak Squires)
- Nov 2020: "Respectfully, I am no longer going to support Fortune 500s… send me a six figure yearly contract or fork the project." Nobody did. **2022-01-06** he shipped `colors@1.4.44-liberty-2` (infinite loop) and `faker@6.6.6`; npm reverted, GitHub suspended his account, the community forked to fakerjs.dev and he lost the project.
- **Lesson:** "Pay me or else" with no product behind it produced zero contracts and destroyed the asset. The fork succeeded him *because* the licence was MIT — RED's leverage is service and roadmap, never withholding the code.
- **Sources:** https://www.bleepingcomputer.com/news/security/dev-corrupts-npm-libs-colors-and-faker-breaking-thousands-of-apps/

#### Cachet (James Brooks / Alt Three)
- Open-source status page (2014); "#1 on Hacker News, top of Product Hunt, Fortune 50 users." Sold ~2018 to buyers with "big plans" that "never came to life"; Brooks: "Within just a few weeks, my brother passed away and my first daughter was born. After that, I never felt right working on Cachet." Drifted ~5 years; **Aug 2023 he bought it back**; v3 rebuild funded by GitHub sponsors, "zero" price, no cloud.
- **Lesson:** Massive launch traction with no revenue line converts into an *acquisition at hobby valuation*; the acquirer's incentives decide the project's fate. Solo projects die on personal events; a paying customer base is the only thing that makes a hand-over survivable.
- **Sources:** https://laravel-news.com/cachet-v3-announcement · https://cachethq.io/

#### Papercups (YC S20) and Meli
- **Papercups:** "open-core Intercom alternative" (Elixir, MIT, ~6.1K stars), 2 founders, YC. README today: **"Papercups is in maintenance mode… there won't be any major new features"**; hosted cloud reportedly shut; entity pivoted to Linen.dev. The founders' post-mortem page returns 404 with an expired cert. **Lesson:** "open-source alternative to [big SaaS]" draws stars from self-hosters and revenue from nobody, because the people who'd pay Intercom prices want Intercom's *service*. RED's paying buyer is the team that would otherwise pay Sentry/Honeybadger — sell them the reasons they'd leave (data residency, cost at volume, Rails-native), not "it's open."
- **Meli:** "open-source Netlify," Dec 2020, 2.4K stars, MIT; last release 1.0.0-beta.24 (2021); repo reads "We are looking for maintainers!" No hosted product ever shipped. **Lesson:** the most common OSS-business failure is silent: a launch, a star spike, no priced offer within the first months, then abandonment. Ship something purchasable within a quarter of announcing it.
- **Sources:** https://github.com/papercups-io/papercups · https://news.ycombinator.com/item?id=24133719 · https://github.com/getmeli/meli

### What the channels actually pay (industry data, 2023–2026)
- **Tidelift 2024 State of the Maintainer (n=437):** **60% of maintainers are unpaid hobbyists**; 24% semi-professional; **only 12% earn most/all income from maintenance**; **60% have quit or considered quitting** (22% quit). Income channels: donation programs 25%, employer salary 24%, Tidelift 19%, direct company payments 5%, individuals 5%, foundations 3%. Tidelift was acquired by Sonar.
- **GitHub Sponsors:** "$40M+ given back to maintainers," 4.2K+ sponsoring organisations — over ~6 years, an average that rounds to a few hundred dollars per sponsored developer per year. Removed PayPal in Jan 2023.
- **Open Source Pledge (Aug 2026):** 47 member companies, **$7.27M pledged since Oct 2024**, minimum $2,000/developer/yr. Sentry's 2025 $750K went 50% via thanks.dev (dependency-graph split), 33% to foundations, 10% funds, 7% GitHub Sponsors — small gems receive *dollars to low hundreds* unless directly named.
- **Open Collective:** host fees 5–15%. Verified run-rates: curl ~$90K/yr, core-js ~$25K/yr, Dokku ~$10K/yr, Sindre ~$7K/yr, Uptime Kuma ~$1.6K/yr.
- **Polar.sh (merchant of record):** 5% + $0.50 per transaction; useful for selling licence keys without a company entity for VAT.
- **FLOSS/fund:** $1M/yr, $10K–$100K grants, application-based.

### Monetisation channel → realistic annual yield for a solo maintainer at ~40K downloads / ~100 stars

| Channel | Realistic yield, year 1 (USD) | Ceiling seen in cohort | Evidence / derivation |
|---|---|---|---|
| GitHub Sponsors / Open Collective button | **$0–$600** | ~$70K/yr (Coolify, 45K stars) | Uptime Kuma 90K stars → ~$1.6K/yr; Dokku 25K → ~$10K/yr; Plausible's self-host base → $300/mo. Scaling to 100 stars gives tens of dollars/month. |
| Sponsorware / gated screencasts ($10–15/mo) | **$0–$3K** without an audience | $112K/yr in 6 months (Porzio) | Needed 75 sponsors from a large Laravel following; $725K of his $1M was screencasts. RED has no list yet. |
| **Paid self-hosted "Server" licence key** | **$3K–$25K** (5–30 orgs at $600–$1,200/yr) | Avo $900–$3K/app/yr supports 2+ people; OpenFaaS $15K/customer; Dokku Pro $849 once | Rallly got price pushback at $49–$299; Avo's per-app, no-per-seat pricing is the Rails-validated band. Assumes 0.1–0.5% conversion of installs. |
| Hosted / Cloud tier | **$2K–$15K ARR** in year 1; marketing-limited | $11M ARR (Ghost, 12 yrs, team); $1M ARR at 3 yrs (Plausible, 2 people); ~$180K/yr (Coolify cloud, 18 months) | Solo comparables: Fider ~$12K/yr plateau; Typebot ~$11.5K/yr run-rate after 18 months. Ops cost per tenant for error ingestion is higher than for RSS or analytics. |
| Enterprise support / LTS / retainer | **$0–$10K** (0–2 contracts) | Stenberg tiers $2K–$50K/yr; Valsorda six retainers = Google comp | Requires a security process, LTS branch, SLA, often a host entity; a "design partner" tier for 3–6 Rails shops at $2K–$5K/yr is the plausible solo version. |
| Tidelift subscription income | **$0–$600** | ~$12K/yr (core-js at 250M downloads/mo) | A 40K-download gem is unlikely to be in many subscriber manifests. |
| Open Source Pledge / thanks.dev distributions | **$0–$300** | $10K–$30K (named foundations only) | Dependency-graph split across thousands of packages. |
| FLOSS/fund or similar grant | **$0 or $10K–$100K** (binary) | $100K | Requires a `funding.json` and a compelling case. Highest expected value of any non-product channel for RED. |
| Paid docs / book / course (standalone) | **$0–$5K** | $2.5M (Refactoring UI, huge audience) | Tracks audience size; better used as the content inside a sponsor tier. |
| Partner/logo sponsorship | **$0–$2K** | Covers salary + 12 contributors (TanStack, 3M visitors/yr) | Nothing to sell at current traffic; 2–3 Rails-hosting/APM vendors at $100–$200/mo become realistic at a few thousand monthly docs visitors. |
| Consulting / "engineering as marketing" | **$5K–$30K**, time-for-money | Alex Ellis sustained OpenFaaS this way pre-Pro | Most reliable early cash; every hour sold is an hour not building the paid edition. |

**Net read:** at today's scale the only channels with material expected value are (a) a priced Server/Enterprise edition with a licence key aimed at teams, (b) a few enterprise design-partner/support retainers, and (c) a grant application. Donations, Tidelift, Pledge distributions and partners are all sub-$1K until the project is 100× larger. The hosted tier is the long-run business (every $1M+ case here is hosted-revenue) but is marketing-bound, so it pays off only if a second person or a serious content engine exists.

### Patterns across Cohort IV
1. Donations scale with *audience*, not usage, and cap around one salary. Nothing in the data suggests a 100-star project clears $1K/yr from donations.
2. Every durable solo income came from a priced product with a distinct buyer: hosted tier, licence key for the team build, retainers/support, or gated education. Sponsorware and partners were accelerants.
3. The free edition must stay useful and un-nagged; the paid edition sells guarantees and org features. The two cases that punished free users (core-js postinstall, faker sabotage) ended in hate mail and a lost project.
4. Licence restriction happened early and cheaply or not at all. Plausible flipped MIT→AGPL at ~$500 MRR with no damage; Bitwarden's late transitive restriction blew up in 48 hours; Gitea's opaque company formation caused a permanent fork.
5. Single-funnel dependency is the modern failure mode (Tailwind/AI, Porzio/PayPal, core-js/npm). Survivors own the payment rail, the email list, and an in-product upsell.
6. Solo capacity, not demand, is the limit. Pricing tiers that include "no support" or "community only" are how one person stays solvent.
7. A second person doing marketing/content is the difference between $1K MRR and $80K MRR.
8. The enterprise sale is a *trust* product — LTS, security backports, SLA, named engineer, roadmap access, procurement-friendly invoicing — frequently sold through a bigger host because procurement won't sign with one person.

---
<a id="cohort-v"></a>
## 8. Cohort V — Licences, forks and rug-pulls

What preserved trust, what destroyed it, and what structurally worked. The through-line: users feel *features*, lawyers feel *licences*, and forks are made of *people*.

### Part 1 — Relicensing backlash and forks

#### HashiCorp / Terraform → OpenTofu → IBM
- **What happened:** 2023-08-10: Terraform, Vault, Consul, Nomad moved from MPL 2.0 to BSL 1.1. Within days the "OpenTF manifesto"; within weeks the Linux Foundation accepted a fork of Terraform 1.5.x as OpenTofu. 2024-04-24: IBM announced a $6.4B acquisition (closed 2025-02-27). OpenTofu became a CNCF sandbox project April 2025.
- **Stated rationale:** "Vendors who provide competitive services built on our community products will no longer be able to incorporate future releases, bug fixes, or security patches."
- **Community reaction / fork outcome:** The manifesto: under BUSL "every company, vendor, and developer using Terraform has to wonder whether what they are doing could be construed as competitive with HashiCorp's offerings." The fork was backed by the commercial ecosystem HashiCorp had targeted (Gruntwork, Spacelift, env0, Scalr) plus AWS/Google/Cloudflare as signatories. HashiCorp sent OpenTofu a cease-and-desist over alleged code copying in 2024, which OpenTofu rebutted.
- **Financial outcome:** FY2024 revenue $583M, roughly in line with guidance given *before* the BSL move. No visible revenue inflection. The relicense is widely read as pre-sale hygiene; IBM paid $6.4B nine months later. It "worked" as exit enablement and permanently created a foundation-governed competitor.
- **Promised vs done:** No written non-relicensing commitment; the ecosystem had an implicit promise that MPL was permanent, and that absence is what the manifesto attacked.
- **Lessons for RED:** The fork came from *commercial* users; if RED sells to consultancies/hosters, they fork if terms shift. "Competitive use" clauses are read as a threat to everyone — define any restriction by concrete act ("reselling RED as a hosted service"), not by "competition." A licence change without a prior written commitment reads as a rug-pull even when defensible. Relicensing raised acquisition value but cost the community forever; for a solo maintainer with no exit plan, that trade is all cost.
- **Sources:** https://www.hashicorp.com/blog/hashicorp-adopts-business-source-license · https://opentofu.org/manifesto/ · https://en.wikipedia.org/wiki/HashiCorp · https://pivotnine.com/blog/hashicorps-license-change-a-strategic-error/

#### Redis → Valkey → Redis back to AGPL
- **What happened:** 2024-03-20: Redis 7.4+ moved from BSD-3 to dual RSALv2/SSPLv1. Within days the Linux Foundation announced Valkey (AWS, Google Cloud, Oracle, Ericsson); core maintainers moved to it. AWS made Valkey the default for new ElastiCache. antirez rejoined Redis late 2024. 2025-05-01: Redis 8 shipped under AGPLv3.
- **Stated rationale (2024):** "the majority of Redis' commercial sales are channeled through the largest cloud service providers, who commoditize Redis' investments." FAQ: "we openly acknowledge that this change means Redis is no longer open source under the OSI definition."
- **Stated rationale (2025 reversal), Rowan Trollope:** "This achieved our goal—AWS and Google now maintain their own fork—but the change hurt our relationship with the Redis community."
- **Community reaction / fork outcome:** Percona: 9 of 24 active Redis contributors (37.5%) stopped contributing; Valkey grew from 18 contributors to 49; in 2025 Valkey opened 865 PRs vs Redis's 537. Valkey displaced Redis as the default package in most Linux distributions and on ElastiCache. The reversal did not bring the fork back.
- **Financial outcome:** Private; company claims "record growth." What is verifiable: hyperscalers stopped shipping Redis, took engineers with them, and the company reversed course 13 months later.
- **Promised vs done:** 2018 post literally titled "Redis license: BSD will remain BSD," which the 2024 announcement itself links to. The 2024 post: "In practice, nothing changes for the Redis developer community." Both false within a year.
- **Lessons for RED:** "Nothing changes for you" is the phrase every rug-pull uses — never say it; enumerate exactly what changes for whom. The most expensive loss was people, not code. A written "X will remain Y" that is later broken is worse than no promise. AGPL is now the "safe" copyleft landing zone for infra companies; for RED, MIT→anything is still a change — pick the permanent licence now.
- **Sources:** https://redis.io/blog/redis-adopts-dual-source-available-licensing/ · https://redis.io/blog/agplv3/ · https://antirez.com/news/151 · https://www.percona.com/blog/community-erosion-post-license-change-quantifying-the-power-of-open-source/

#### Elastic → OpenSearch → Elastic back to AGPL
- **What happened:** Jan 2021 (v7.11): Elasticsearch and Kibana moved from Apache 2.0 to dual SSPL / Elastic License. Apr 2021: AWS forked as OpenSearch. 2024-09-16: AWS transferred OpenSearch to the Linux Foundation (>700M downloads then, >1B by 2025). 2024-08-29: Shay Banon's "Elasticsearch is Open Source, Again" added AGPLv3.
- **Stated rationale (2021):** cloud providers "taking open source products and providing them as a service without investing back," plus trademark misuse. Elastic promised: "We remain committed to keeping all of our free features free."
- **Stated rationale (2024):** "We had issues with AWS and the market confusion their offering was causing… it worked. 3 years later, Amazon is fully invested in their fork… our partnership with AWS is stronger than ever."
- **Financial outcome:** FY2024 revenue $1.267B, up 19%; Elastic Cloud growing 32%. Commercially it worked — Elastic's own cloud grew once AWS stopped selling "Elasticsearch." Cost: a permanent competitor with a billion downloads, and a public reversal.
- **Promised vs done:** 2018: "We are an open source company. We will remain an open source company." 2021 broke the licence promise but kept the *feature-level* promise ("all free features stay free"). The feature promise being kept is why the backlash was survivable.
- **Lessons for RED:** Feature-level promises are the ones users feel. The change "worked" only because Elastic had a cloud to sell against AWS; RED has no hyperscaler threat and nothing for a restrictive licence to protect. Banon's admission that moving off open source "had always been a point of tension internally" shows the reputational tax is paid every day.
- **Sources:** https://www.elastic.co/blog/licensing-change · https://www.elastic.co/blog/doubling-down-on-open · https://www.elastic.co/blog/elasticsearch-is-open-source-again · https://en.wikipedia.org/wiki/OpenSearch_(software)

#### MongoDB (SSPL, 2018)
- 2018-10-16: Community moved from AGPL to SSPL. OSI declared SSPL non-open-source (Jan 2021). Debian, Fedora and RHEL dropped MongoDB packages. Rationale: Alibaba, Tencent and Yandex "testing the boundaries of the AGPL." No viable fork of the server. **Financial outcome:** unambiguous success — fiscal 2026 revenue $2.46B, up 23%; Atlas ~75%. **Promised vs done:** MongoDB never made a "forever open" promise; it had a CLA from day one.
- **Lessons for RED:** Relicensing "worked" only for a company with a cloud product, a CLA, and no competitor able to fork. RED has none of those. The absence of a prior promise reduced the betrayal; RED's "free, forever" tagline *is* a promise. Distro removal is a quiet, permanent adoption tax; RubyGems has no such gate, but Rails-community blessing (Ruby Weekly, awesome-ruby, Ruby Toolbox) works the same way.
- **Sources:** https://www.theregister.com/2018/10/16/mongodb_licensning_change/ · https://www.mongodb.com/legal/licensing/server-side-public-license/faq · https://investors.mongodb.com/

#### Lightbend / Akka → Apache Pekko; CockroachDB; Mapbox GL → MapLibre; Bitwarden
- **Akka:** Sep 2022, Apache → BSL 1.1 (free for organisations under $25M revenue). Apache Pekko (fork of 2.6.x) 1.0.0 July 2023. Play Framework deliberately stayed on Akka 2.6. **Lesson:** revenue-threshold licences *feel* fair but still forced the ecosystem to fork, because downstream libraries cannot ship a dependency whose licence their users must individually evaluate. If RED ever becomes a dependency other gems extend, its licence is effectively frozen.
- **CockroachDB:** 2019 Apache → BSL (Core free, Enterprise paid). Aug 2024: Core retired; single "Enterprise" licence, free under $10M revenue. Zaitsev: "becoming yet another Oracle." InfoQ: Core "made the Enterprise license palatable since users could fall back to Core features… now there's no such mitigation." **Lesson:** users value a fallback edition they can stay on forever more than a generous-but-revocable grant. RED's MIT core *is* that fallback; never fold it into a gated edition.
- **Mapbox GL JS:** Dec 2020 v2 proprietary (requires a Mapbox token); v1.13 (BSD) forked as MapLibre within weeks; now a foundation-style project funded by Amazon, Meta, Microsoft, Elastic. **Lesson:** a client library/SDK is the easiest thing to fork and the hardest to win back. If RED ships a browser or agent SDK, keep it MIT regardless.
- **Bitwarden (Oct 2024):** desktop client pulled in `@bitwarden/sdk-internal` whose licence forbade use "with software other than Bitwarden"; issue #11611 went viral within a day; Bitwarden called it a "packaging bug," restructured the build, relicensed the SDK to GPLv3 (2024-11-04). No fork; resolved in ~two weeks because the reversal was total and fast. **Lesson:** audit every dependency and sub-package licence; a proprietary piece pulled in by the MIT gem will be read as the rug-pull.
- **Sources:** https://blog.lunatech.com/posts/2023-10-27-akka-licence-change-one-year-later · https://pekko.apache.org/ · https://www.theregister.com/2024/08/19/cockroachdb_abandons_open_core/ · https://www.infoq.com/news/2024/09/cockroachdb-license-concerns/ · https://thenewstack.io/maplibre-how-a-fork-became-a-thriving-open-source-project/ · https://github.com/bitwarden/clients/issues/11611 · https://www.theregister.com/software/2024/11/04/bitwarden-switches-password-manager-and-sdk-to-gpl3/

#### Sentry (brief)
- Nov 2023: BSL → Functional Source License (source-available for any non-competing use; automatic conversion to Apache/MIT after two years). 2024: "Fair Source" (fair.io); funded the OSI's DOSP study. **Lesson:** FSL is the most trust-preserving *non*-open-source option because the conversion date is contractual and short. But Sentry's self-hosted tier is the competitor RED is positioned against; RED's advantage is precisely that it is MIT and Sentry is not.
- **Sources:** https://blog.sentry.io/introducing-the-functional-source-license-freedom-without-free-riding/ · https://fair.io/about/

### Part 2 — Feature removal and "moving features to paid"

#### MinIO (2025)
- **What happened:** 2025-02-26 (commit by a co-founder): the Community Edition console lost account/policy management, configuration, bucket management, lifecycle/tiering and site replication, leaving a bare object browser. Not called out in the changelog. Later in 2025 the `minio/minio` README was changed to "THIS REPOSITORY IS NO LONGER MAINTAINED," directing users to "AIStor Free" and "AIStor Enterprise"; the community repo gets no new features, no PR/issue review, and security fixes "case-by-case."
- **Stated rationale:** "Building and supporting separate graphical consoles… is substantial… Admin actions in the console lack equivalent security protections. Without dedicated maintenance, this code risks introducing security vulnerabilities."
- **Community reaction:** "It's weird as there's not a single warning about this in the changelog." OpenMaxIO forked the old console UI; it stalled within months. Industry perception: MinIO used open source as a growth hack and closed the door once enterprise revenue arrived.
- **Financial outcome:** Private. Commercial licensing reportedly starts at $96K/yr (competitor claim). No evidence the removal hurt revenue; strong evidence it ended MinIO's reputation as the default self-hosted S3 and spawned the "MinIO alternatives" industry (Garage, SeaweedFS, Ceph RGW, RustFS).
- **Lessons for RED:** RED's dashboard *is* the product; MinIO is the closest analogue. Removing UI/admin features from the free edition is the single most damaging thing a dashboard project can do. Silent removals (no changelog entry) convert a business decision into a scandal. "Security" as the justification for gating admin features is not believed — if a feature is a security risk in the free tier, fix it, don't sell it. A stalled fork means the community gave up on the product entirely.
- **Sources:** https://blocksandfiles.com/2025/06/19/minio-removes-management-features-from-basic-community-edition-object-storage-code/ · https://github.com/minio/minio (README) · https://github.com/OpenMaxIO/openmaxio-object-browser · https://bizety.com/2025/12/06/minio-in-maintenance-mode-open-source-alternatives/

#### Rocket.Chat, Docker Desktop, Gitea → Forgejo, Sourcegraph, Chef, Kong, Nginx, Mattermost, Nextcloud
- **Rocket.Chat:** From v6 (Mar 2023) the Community Edition progressively lost read receipts, custom permissions and horizontal scaling; push notifications capped. Dec 2023: a "Starter" plan restored premium features under small user caps. Forum: "RocketChat is no longer a suitable tool for use in organizations"; users migrated to Zulip/Mattermost/Matrix. **Lesson:** removing something that *already shipped free* is the definition of a rug-pull; adding new paid features is not. RED's rule must be temporal: nothing that has ever shipped in the MIT gem moves out of it.
- **Docker Desktop (2021):** 2021-08-31, paid subscription for organisations >250 employees or >$10M revenue; free for everyone else. Loud complaints, Podman/Colima adoption, but Docker Desktop was never open source and the engine (Apache 2.0) never changed, so there was nothing to fork. **It worked:** ARR $165M (2023) → $207M (2024), >1M paid seats. **Lesson:** free OSS core, paid *convenience/packaging* for big companies, size-gated. Because the engine stayed open, the outrage had nowhere to go. The MIT gem is RED's engine.
- **Gitea → Forgejo:** 2022-10-25: Gitea's domains and trademark transferred to a newly formed for-profit, Gitea Ltd, without community consultation. Open letter (51 signatories) asked for a community non-profit to hold the trademark; declined. 2022-12-15: Codeberg e.V. launched Forgejo (hard fork Feb 2024; GPL Aug 2024). Forgejo now default on Codeberg (>300K repos). **Note: no code licence changed** — trust broke on governance and trademark alone. Open letter: "We believed you when you promised to pass along the ownership of the Gitea project to your elected successors." **Lesson:** if RED forms a company, publish now who owns the trademark, the domain and the gem-push rights, and what happens to them.
- **Sourcegraph (Aug 2024):** main repository made private. Quinn Slack: "it added a lot of extra work and risk to have stuff be open source and public"; open source "could make sense" for "infrastructure products or client tools," not "full server-side end-user applications," which receive far fewer external contributions. No fork — the OSS version never built a self-hosting community large enough. **Lesson:** RED is what Slack says OSS does not work for as a go-to-market — but a Rails engine gem is closer to "client tool" than a SaaS; it is installed into the user's app, which is exactly the distribution channel Sourcegraph lacked. Keep RED a gem. Budget the "extra work and risk" explicitly. If RED cannot be sustained, say so and hand the MIT core to co-maintainers; Sourcegraph's silent close is the anti-pattern.
- **Chef (2019–2020):** 2019-04-02, all product code Apache 2.0, *binaries* commercial for production use. Community rebuilt binaries as Cinc; the FAQ pre-acknowledged forks. Sep 2020: Progress acquired Chef for ~$220M. Code stayed Apache through the acquisition. **Lesson:** charging for build/distribution while the code stays open is a trust-preserving split, especially when the maintainer says out loud "you may fork this." Adam Jacob: "There isn't an open source business model. That's not a thing… open source is a channel."
- **Kong:** Gateway Apache 2.0; Enterprise/Konnect carry analytics, catalog, portal, support. No relicensing event. **Lesson:** "data plane free, control plane/analytics paid" — error capture and the core dashboard free; fleet-wide analytics paid. Kong avoided a fork by never moving anything out of OSS.
- **Nginx → F5:** Acquired 2019 for $670M; Dec 2019 Moscow police raid; Angie (2022) and freenginx (Feb 2024, core maintainer Maxim Dounin citing "F5's interference") forks. Nginx OSS still holds ~34% share. **Lesson:** an acquirer can lose the *maintainer* even while the licence and market share hold. NGINX Plus is a clean "operations dashboard is paid" split that survived 15 years without a removal scandal.
- **Mattermost (v11, Oct 2025):** free Team Edition lost GitLab OAuth; a new "Entry Edition" enforces a 10,000-message-per-channel limit on self-hosted instances — older messages hidden even though they sit in the user's own database. Forum: "paying 400$ a month for something I'm self-hosting is extortionate"; "What additional costs does it incur for Mattermost? NONE, because it's on my machine." A school with 470,000 messages lost access to its history. Fork: Mostlymatter. **Lesson:** artificial limits on data the user already stores are read as hostage-taking, not pricing. RED must never gate access to error data the user's own Postgres/SQLite holds.
- **Nextcloud vs ownCloud (2016):** Frank Karlitschek and 9 of ownCloud's top 10 contributors forked over "short term money or long term responsibility." Nextcloud made everything AGPL and sells support subscriptions; no proprietary code. ownCloud GmbH was acquired by proprietary vendor Kiteworks (2023). Nextcloud won decisively. **Lesson:** the fork won by taking the *people* and promising "no enterprise-only code."
- **Sources:** https://forums.rocket.chat/t/rocketchat-is-no-longer-a-suitable-tool-for-use-in-organizations/16513 · https://www.infoq.com/news/2021/09/docker-desktop-subscriptions · https://sacra.com/c/docker/ · https://gitea-open-letter.coding.social/ · https://blog.codeberg.org/codeberg-launches-forgejo.html · https://devclass.com/2024/08/21/sourcegraph-makes-core-repository-private-co-founder-complains-open-source-means-extra-work-and-risk/ · https://devclass.com/2019/04/02/chef-says-its-going-100-open-source-forks-optional/ · https://changelog.com/podcast/353 · https://en.wikipedia.org/wiki/Nginx · https://forum.mattermost.com/t/a-critical-response-to-mattermost-s-recent-changes/25407 · https://nextcloud.com/blog/press_releases/pr20160602/

### Part 3 — The RethinkDB post-mortem (Slava Akhmechet, Jan 2017)
- Oct 2016: RethinkDB shut down after ~8 years and ~$12M raised.
- **Core diagnosis:** "we picked a terrible market and optimized the product for the wrong metrics of goodness." "You're not in the market you think you're in — you're in the market your users think you're in." RethinkDB thought it was a database company; it was "an open-source developer tools company."
- **Why developer tools are a terrible market:** "Developers love building developer tools, often for free," which "drives the number of alternatives up, and the prices down to zero." Even the winners are small. Result: "an intractable customer acquisition funnel."
- **Willingness to pay:** users "were willing to pay less for the lifetime of usage than the price of a single Starbucks coffee (which is to say, they weren't willing to pay anything at all)."
- **Wrong metrics of goodness:** RethinkDB optimised for correctness, simplicity, consistency. Users wanted "Timely arrival," "Palpable speed," and use-case focus. "Correct, simple, and consistent software takes a very long time to build. That put us three years behind the market."
- **His takeaways:** "Pick a large market but build for specific users"; "Learn to recognize the talents you're missing, then work like hell to get them on your team."
- **Lessons for RED:** RED's market is "Rails developer tools" — many free substitutes (exception_notification, Sentry free, Honeybadger free, Rails' own error reporter), so individual willingness to pay is ~zero. Plan revenue from teams whose *time* is expensive (Rails shops, enterprises), for whom "we host it / we support it / it passes our audit" is the product. Ship the paid editions while RED has momentum. Build the enterprise edition for one concrete buyer profile (e.g. the platform team at a 50-engineer Rails shop that cannot send errors to a third-party SaaS). The missing talent for a solo maintainer is sales and pricing.
- **Sources:** https://gist.github.com/ramalho/93b87e961b6e019be8e1f6f82864b6f9 (mirror) · https://rethinkdb.com/blog/rethinkdb-shutdown/

### Part 4 — Structural playbooks that held trust

#### GitLab stewardship page (verbatim)
1. "When a feature is open source we won't move that feature to a paid tier."
2. "We won't introduce features into the open source codebase with a fixed delay, if a feature is planned to land in both it will be released simultaneously in both."
3. "We will always release and open source all tests that we have for a open source feature."
4. "The open source codebase will have all the features that are essential to running a large 'forge' with public and private repositories."
5. "The open source codebase will not contain any artificial limits (repositories, users, size, performance, requiring a trademarked header, etc.)."
6. "All stages of the DevOps lifecycle… will have some open source features."
7. "The majority of new features made by GitLab Inc. will be open source."
8–10. Downloadable without giving an email; benchmarking allowed; free-tier options clearly discoverable.
11. "We will always make it clear what is proprietary and what is open source code."

Tiering rule: "Who cares the most about the feature." If the likely buyer is an individual contributor → open source (Free); a manager → Premium; a director/executive → Ultimate. The split is by *feature*, never by codebase. **Kept:** features have only moved *down* (e.g. an 18-feature batch to Core, March 2020). **Why it works:** the rule is falsifiable; anyone can check whether a feature moved tiers.
- **Sources:** https://handbook.gitlab.com/handbook/company/stewardship/ · https://opencoreventures.com/blog/2023-01-open-core-standard-pricing-model/ · https://about.gitlab.com/blog/new-features-to-core/

#### PostHog
- MIT repo with an `ee/` directory under the PostHog Enterprise License; a separate `posthog-foss` repo strips every proprietary file so a fully MIT build exists. Pricing, roadmap, salaries public.
- **Pricing principles (verbatim):** "Use PostHog for free if they are hobbyists or pre-PMF"; "Features that are focused around extra security, permissioning, compliance, or other enterprise-style upgrades should be reserved for our enterprise pricing tier"; "Features that increase our stickiness should be free"; "Features that have the potential to grow our word-of-mouth should be free – e.g. we shouldn't (and don't) charge for extra users"; "It's easy to increase the free tier for existing customers, but it's very painful to decrease it."
- **The 2023 self-hosted decision:** Helm-chart updates stopped 2023-05-31; security patches ≥12 months. Only 3.5% of users were on Kubernetes. Paid self-hosted licences discontinued; the MIT Docker Compose "hobby" deployment continued. Affected customers got three paths. No fork, no backlash — the free edition lost nothing, the affected group was small and told the truth, migration paths and a 12-month window were explicit.
- **Lessons for RED:** The `ee/` + `-foss` pattern proves the MIT build is complete; better still, ship `rails_error_dashboard` (MIT, complete) and a separate enterprise gem (Bitwarden shows how a bundled proprietary piece reads). Never charge per seat. When RED cannot support some deployment shape, copy the PostHog script: name the percentage, keep patches ≥12 months, give three exits.
- **Sources:** https://posthog.com/handbook/engineering/feature-pricing · https://posthog.com/blog/sunsetting-helm-support-posthog · https://github.com/PostHog/posthog

#### Metabase, n8n, Grafana, Supabase, Plausible CE, Odoo, WordPress, Commons Clause
- **Metabase:** AGPL edition; Pro/Enterprise commercial (SSO, row-level permissions, white-labelling). Embedding: comply with AGPL, or free embedding with "Powered by Metabase," or buy a licence to remove branding. **Lesson:** "Powered by RED" attribution in the free dashboard, removable in paid, is a legitimate, non-punitive lever.
- **n8n:** Mar 2022, Apache + Commons Clause → its own Sustainable Use License (free for "internal business purposes"; cannot host as a service for third parties; consulting explicitly allowed). €55M Series B (Mar 2025), reported $180M at ~$2.5B (Oct 2025); ~$40M ARR (est.). Held because n8n was *never* OSI-open-source at scale and the licence was made *looser*. **Lesson:** the n8n path is closed to RED without a rug-pull; "you may not resell RED as a hosted service" must be a *trademark* rule, not a licence change.
- **Grafana:** Apr 2021 Apache → AGPLv3; "considered SSPL and watched community response to MongoDB and Elastic"; chose AGPL because OSI-approved. No fork; >$400M ARR. **Lesson:** if RED ever needs copyleft, AGPL is the one move repeatedly accepted — and still a change to justify. Decide now and don't move.
- **Supabase:** Apache/MIT/PostgreSQL components; self-hostable; revenue from cloud; >$250K sponsorships upstream. **Lesson:** "everything open, cloud is the product" works when hosted is materially easier than self-hosting. RED Cloud should compete on convenience, not withheld features.
- **Plausible CE (2024):** "We want to reduce the threat from businesses such as hosting companies and other resellers who try to commercialize popular open source projects." "Nothing from Plausible CE will be taken away in the future." Explicit rejection of non-OSI licences. Kept. **Lesson:** protect the *name*, not the code; delay some new features to CE rather than removing any.
- **Odoo:** Since v9 (2015) Community LGPLv3, Enterprise proprietary. €282M revenue 2023, $5.26B valuation 2024. A decade of open core without a fork of note; the OCA reimplements many Enterprise features as community modules and Odoo tolerates it. **Lesson:** a blessed community-extension path is a pressure valve.
- **WordPress / WP Engine (2024–25):** GPL never changed. Mullenweg called WP Engine "a cancer," demanded ~8% of revenue, cut WP Engine off from wordpress.org update servers, took over its plugin listing. Lawsuit; injunction; ~159 Automattic staff took a buyout; Automattic laid off ~16%. Forks appeared for the *distribution layer* (AspirePress, FAIR). **Lesson:** the rug-pull vector is whatever central chokepoint the maintainer controls (gem name, update channel, hosted service, domain). Document what those are and what happens if the maintainer's interests change.
- **Commons Clause (2018):** Neo4j and Redis Labs appended "no selling the software" to AGPL/Apache. Widely attacked as source-available masquerading as open source; Redis Labs dropped it within a year ("confused" users). **Lesson:** bolting a restriction onto a familiar OSI licence is the worst of both worlds.
- **Sources:** https://www.metabase.com/license/ · https://blog.n8n.io/announcing-new-sustainable-use-license/ · https://grafana.com/blog/qa-with-our-ceo-on-relicensing/ · https://supabase.com/open-source · https://plausible.io/blog/community-edition · https://en.wikipedia.org/wiki/Odoo · https://techcrunch.com/2025/01/12/wordpress-vs-wp-engine-drama-explained/ · https://www.theregister.com/2019/02/22/redis_labs_changes_license_funding_60m/

### Part 5 — The SSO tax and "security features are off-limits"
- **sso.tax:** "SSO is a core security requirement for any company with more than five employees." Threshold: "If your SSO support is a 10% price hike, you're not on this list." Documented markups run 100% to >9,000%.
- **The self-hosted twist:** for self-hosted software the SSO tax is felt as extortion because the customer already pays for infrastructure (Mattermost, Rocket.Chat threads).
- **Where the community draws the line:**
  - *Off-limits to gate:* basic SSO/OAuth login (at minimum one OIDC/SAML path), 2FA, security patches, encryption, access to the user's own stored data, exports.
  - *Accepted to gate:* SSO *enforcement* and SCIM provisioning, fine-grained/group-mapped RBAC, audit-log retention/export to SIEM, compliance reports, multi-org/tenant management, white-labelling, hosted operation, support SLAs.
  - 1Password's framing: SSO was "a sunroof," is now "a rearview camera" — a safety baseline. PostHog and GitLab gate *advanced* security (SAML group sync at Premium), not *baseline* security.
- **Lesson for RED:** ship OIDC/SAML *login* free (already effectively true via pluggable auth); charge for enforcement, provisioning, group-mapped RBAC, audit export. Flat rate, not per seat.
- **Sources:** https://sso.tax/ · https://github.com/stopthessotax/sso-wall-of-shame · https://1password.com/blog/explaining-the-backlash-to-the-sso-tax

### Part 6 — Frameworks and research
- **Buyer-based open core (Sijbrandij / Open Core Ventures):** split by *feature*, never by codebase; tier set by "who cares most"; features only move down. — https://opencoreventures.com/blog/2023-01-open-core-standard-pricing-model/
- **Peter Levine, a16z:** three sequential fits — project-community fit, product-market fit, value-market fit ("typically centers on departmental and enterprise buyers"). "Sometimes an OSS product can be too good… there is no natural extension to drive revenue." Open core "risks community alienation if boundaries feel unfair." "Open source is top-of-funnel activity." PlanetScale-style rule: "keep open source anything that would produce vendor lock-in." — https://a16z.com/open-source-from-community-to-commercialization/
- **Adam Jacob (Chef), "The War for the Soul of Open Source":** "There isn't an open source business model. That's not a thing… open source is a channel." Open core draws a line that inevitably moves under commercial pressure; the durable asset is a community with shared values. — https://changelog.com/podcast/353
- **OSI, "Delayed Open Source Publication" (2024, Sentry-funded):** DOSP is trust-neutral only when the conversion date and target licence are fixed in the licence text (FSL's 2 years → Apache/MIT), and trust-negative when applied *retroactively* to a project that was already open (HashiCorp, Akka). — https://opensource.org/delayed-open-source-publication
- **Fair Source (fair.io):** publicly readable; use/modify/redistribute "with minimal restrictions to protect the producer's business model"; guaranteed DOSP. — https://fair.io/about/

### Patterns across Cohort V
1. **Every rug-pull was a broken *prior* promise, explicit or implied.** MongoDB (no promise) survived relicensing cleanly; Redis and Elastic (explicit promises) were forced to reverse. RED's "free, forever" tagline is already a promise.
2. **Feature removal hurts more than licence change.** Elastic kept "all free features stay free" and grew; MinIO, Rocket.Chat and Mattermost removed shipped features and lost their self-hosting base.
3. **The free edition must be complete for its buyer.** GitLab #4 and Plausible held; CockroachDB's loss of a Core fallback narrowed trust to exactly the size of what remained free.
4. **No artificial limits on the user's own data.** Mattermost's cap is the canonical outrage; GitLab #5 exists to forbid it.
5. **Charge for what a manager or director signs for; never for what a developer needs to do the job.** Baseline security sits on the developer side of the line.
6. **Revenue came from hosting, packaging and size-gating — not from restricting code.** Docker, Grafana, MongoDB Atlas, n8n all monetise the hosted/packaged product.
7. **Forks are made of people, not code.** Redis lost 9 of 24 contributors; Nextcloud took 9 of ownCloud's top 10; freenginx was one maintainer.
8. **Silence is the multiplier.** MinIO's unannounced commit and Gitea's undisclosed transfer turned defensible moves into scandals. PostHog and Chef announced constraints in advance, with percentages, dates and exits, and were forgiven.
9. **Governance chokepoints are rug-pull vectors even under GPL/MIT.** WordPress (update servers), Gitea (trademark/domain), Nginx (acquirer vs maintainer).
10. **Developer tools have near-zero individual willingness to pay (RethinkDB).** Plan revenue from teams whose time is expensive; do not punish indies for not converting.

---

<a id="ledger"></a>
## 9. The promise ledger

| Project | The promise (quoted) | Held? |
|---|---|---|
| GitLab | "When a feature is open source we won't move that feature to a paid tier." "The open source codebase will not contain any artificial limits." "We will always make it clear what is proprietary and what is open source code." | **Kept** (2016–2026); features have only moved down. |
| Plausible (2024) | "Nothing from Plausible CE will be taken away in the future." Rejects non-OSI licences "to stay open source." | **Kept** so far. |
| PostHog | "It's easy to increase the free tier for existing customers, but it's very painful to decrease it." Free: sticky features and unlimited seats. | **Kept** at feature level; self-hosted *enterprise* withdrawn (2023) with a 12-month patch window and explicit reasons. |
| Chef (2019) | "100% open source" code, Apache 2.0; forks welcome. | **Kept** through acquisition; binaries commercial as stated up front. |
| Elastic | 2018: "We will remain an open source company." 2021: "keeping all of our free features free." | Licence promise **broken** 2021, partially restored 2024; feature promise **kept**. |
| Mattermost | "Team Edition remains fully open source, has no hard user cap." | Letter kept, spirit **broken**: features stripped, message caps. |
| Redis (2018) | "Redis license: BSD will remain BSD." 2024: "In practice, nothing changes for the Redis developer community." | **Broken** 2024; reversed to AGPL 2025 after losing maintainers. |
| HashiCorp | "We believe strongly in freely available source code." No non-relicensing pledge. | MPL assumption **broken**; OpenTofu. |
| Gitea | To "pass along the ownership of the Gitea project to your elected successors." | **Broken** 2022 by trademark/domain transfer; Forgejo. |
| Sourcegraph (2018) | Open-sourced to "make basic code intelligence ubiquitous." | **Broken** 2024 (repo private). |
| Spree (2024) | AGPL + "Developer Covenant." | Core **reverted** to BSD in ~15 months. |
| MinIO | None written. | Console admin removed silently; repo now "NO LONGER MAINTAINED." |
| **RED (today)** | "Self-hosted Rails error monitoring — free, forever." | **Ambiguous** — refers to what? |

Pattern: the promises that held were **feature-level, falsifiable and directional** ("nothing moves up"), from companies whose revenue did not depend on withholding the thing promised. The promises that broke were **licence-level or vague** ("we will remain open source") from companies facing a hyperscaler or an exit.

---

<a id="playbook"></a>
## 10. What it means for RED — the playbook

Not a plan of record — the shape the evidence points to. Every line traces to a case above.

### 10.1 Write the trust contract before the first paid edition

**Draft — Rails Error Dashboard stewardship commitments** (distilled from the promises that held: GitLab #1–5 and #11, Plausible CE, PostHog's pricing principles, Chef, Bitwarden)

1. The `rails_error_dashboard` gem is MIT-licensed and will stay MIT. We will not relicense it, add a "commons clause," or move it to a source-available or delayed-open-source licence.
2. When a feature ships in the MIT gem, it stays there. We will never move a feature from the free gem to a paid edition.
3. The free gem has no artificial limits — no caps on apps, users, errors, retention or performance, and no hidden data. Your error data lives in your database and is always fully accessible and exportable.
4. The free gem is complete for a development team: capture, grouping, search, stack traces, notifications, integrations, and the full dashboard. Paid editions add what managers and directors buy — hosting, support with SLAs, SSO enforcement and provisioning, role-based access, audit export, multi-app reporting, and compliance evidence. Basic single sign-on login and every security fix ship free.
5. Paid editions are separate gems or services. Nothing proprietary is bundled into the MIT gem, and every file's licence is obvious.
6. A feature that lands in both editions ships in both at once; no fixed delays.
7. We will never charge per developer seat.
8. Tier changes are announced in the changelog before release, with the reason, and anything ever deprecated gets at least twelve months of security patches and a migration path.
9. If we can no longer maintain RED, we will say so and hand the MIT gem to community maintainers rather than close it.

**The tagline.** "Free, forever" is already a promise, and today it is ambiguous. Rewrite it to what can be kept under any pressure: *"The gem is MIT and free forever."* Then the paid editions are additions, not betrayals. In the same document, publish who owns the trademark, the domain, the GitHub org and the gem-push rights, and what happens to them on acquisition or maintainer exit (Gitea, WordPress).

### 10.2 Split editions by who signs, not by what's clever

| Edition | Buyer persona | What's in it | Precedent |
|---|---|---|---|
| **Community** (MIT gem) | The developer | Everything shipped today: capture, grouping, dashboard, workflow, notifications, issue trackers, i18n, storm protection, deep introspection, pluggable auth (so SSO login via Devise/omniauth is already free). Plus an MCP server — table stakes now. | Sidekiq core · GitLab Free · Plausible CE · Faultline's feature list |
| **Server** | The platform lead / engineering manager at a Rails shop or agency | Fleet: many apps and deployments in one view; cross-app reports; retention and sampling policies; team assignment SLAs; priority support; a "no support" self-serve tier at the bottom. Per organisation, unlimited apps and users, annual, under ~$1K/yr entry. Self-serve licence key from the admin UI; dev/test unlicensed. | Sidekiq Pro · Avo · Chatwoot EE · Rallly · Dokku Pro |
| **Enterprise** | The director / compliance | SSO enforcement + SCIM, group-mapped RBAC, audit export to SIEM, compliance evidence pack, LTS branch with security backports for customers only, named engineer, PO/invoice. Priced in the thousands, sold to a handful. | curl LTS · GitLab Ultimate · SigNoz Enterprise · Grafana Enterprise |
| **Cloud** (last) | Teams that don't want any ops | Hosted Server — the aggregation layer, not the data. Consider selling hosting through a partner (Elestio/DanubeData list GlitchTip and Bugsink) before running it yourself; solo-dev hosted trackers face a trust wall (Telebugs) and hosting is where PostHog's tail lived. | Coolify Cloud · Healthchecks · Discourse (contrast) |

### 10.3 Pricing anchors the record gives you

**The bands**
- Indie willingness-to-pay: €10/mo (RorVsWild). Don't plan revenue from indies (RethinkDB); don't punish them either.
- Team error tracker, hosted: $26/mo is the universal anchor (Sentry, Honeybadger, elmah.io, Flare).
- Rails engine per app, licence key: $75–$249/app/mo (Avo). Perham's line: keep the first tier under $1,000/yr so no VP sign-off is needed.
- Enterprise self-hosted: $4,500/yr (Hangfire) to "5 figures" (Spree EE) to $4,000/mo (SigNoz). Retainers $2K–$50K/yr (curl).

**The rules**
- Annual, never one-time (Perham, Oliver, ONCE).
- Per organisation, unlimited seats (Sidekiq, Hangfire, PostHog, Avo). Never per developer.
- Scale-based pricing only at the top tier (Sidekiq threads).
- Own the payment rail — Stripe/Paddle, not one platform (Porzio, core-js).
- Money-back guarantee and automated billing (Hangfire, Sidekiq).
- Free for OSS projects and nonprofits (Skylight, Healthchecks, Rallly's lesson).

### 10.4 Sequence
- **Now:** stewardship commitments + editions doc + trademark/governance page. Reword the tagline. Register the org and trademark. Add a second maintainer with release rights (Errbit, solid_errors).
- **Before 1.0:** MCP server (Faultline, Scout, Honeybadger all have one); health endpoint and webhook HMAC (procurement questions); instrument, opt-in, who runs RED at scale — those are the first Server buyers (Perham's first ten).
- **1.0:** the stability contract — public API surface, deprecation policy, support window. Solidus forked Spree over upgrade pain; ONCE's market wanted effortless upgrades. This is the enterprise unlock and it is mostly not code.
- **Then Server:** as a separate gem, self-serve key, priced under the VP line, with a "no support" bottom tier and a 3–6 company design-partner tier above it. Ship something purchasable within a quarter of announcing it (Meli; Bugsink's three-month reversal).
- **Then Enterprise:** the standard SKU. Sell through a bigger host if procurement won't sign with one person (curl/wolfSSL).
- **Cloud last, or via a partner.** Apply to FLOSS/fund in parallel — the only non-product channel with real expected value.

### 10.5 Distribution, since it beats product in every story

**Channels with precedent**
- Deploy marketplaces and hosting partners: Heroku made Judoscale; a hosting partner gave New Relic 400 customers on day one. Render, Fly, Hatchbox, Kamal-hosting shops.
- Out-write the incumbents: Honeybadger, AppSignal and Raygun all built on tutorial blogs. Raygun's ranking: content > small meetups > podcasts > small confs.
- Attack Sentry's self-hosting story by name, with the operational-cost comparison (Bugsink's most-shared content). RED's version is stronger: zero extra infrastructure.
- Migration paths from exception_notification, solid_errors, Errbit, exception_hunter — stranded users are cheap acquisition.
- Free Server licences for visible OSS Rails apps (Skylight's best move).

**Channels to skip for now**
- Donation buttons as a plan (Uptime Kuma; Plausible's $300/mo).
- Docs-traffic funnels as the business (Tailwind). Put the upsell in the product.
- "Open-source alternative to Sentry" as the pitch (Papercups). Pitch the reasons a Sentry customer would leave.
- Sponsorware before there is a list (Porzio needed 20K followers).
- Partner/logo tiers until docs traffic exists (TanStack).

### 10.6 The RED-shaped failure modes

| Failure | Who did it | RED's guard |
|---|---|---|
| Solo maintainer with a day job goes quiet at 12–24 months | solid_errors, Faultline, Errdo, Exception Hunter, Meli | A revenue reason to continue; a second maintainer; the paid tier framed as "how it stays maintained." |
| Charging for "production use" of self-hosted software | Bugsink (scrapped in 3 months) | Crisp trigger: organisation size, fleet features, SSO enforcement, SLA. |
| One-time pricing for self-hosted | Sidekiq's first 18 months, ONCE, Tailwind UI | Annual from day one. |
| Removing a shipped free feature, or capping the user's own data | MinIO, Rocket.Chat, Mattermost | Commitments #2 and #3; tier decisions recorded in the changelog. |
| Relicensing the core to force enterprise deals | Spree (reverted), Redis (reverted), HashiCorp (forked) | Commitment #1; proprietary modules around an MIT core. |
| Proprietary code leaking into the free build | Bitwarden SDK (reverted in days) | Commitment #5; separate gems, not an `ee/` folder inside the MIT gem. |
| Depending on a channel you don't control | Flare (Ignition removed), Judoscale (Heroku), Porzio (PayPal), core-js (npm) | The gem is the channel; own the payment rail and the list. |
| Solo hosted SaaS nobody trusts with their data | Telebugs v1 | Cloud last, or via a partner; Server first. |
| Paid self-hosting support eaten by the long tail | PostHog (3.5%), Hatchbox (highest support load) | Known stacks only; "no support" tier; scoped SLAs. |
| Consulting or client work always winning over the product | Flare/Spatie, GlitchTip, Skylight | Ring-fenced hours; a date by which the business pays for itself. |
| Governance chokepoints held opaquely | Gitea, WordPress | Publish ownership of the name, domain, org and push rights. |

---

*End of first edition. Update the ledger and the numbers table when a case moves; note the date of every change.*
