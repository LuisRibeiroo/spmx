# PRD: spmx — Landing Page + Docs + Benchmarks

**Versão:** 1.0  
**Status:** Em implementação (US-001–008 feitas; US-009 parcial; US-010 pendente)  
**Repositório Alvo:** `~/projects/spmx` → novos diretórios `website/` e `bench/`  
**Stack:** Next.js 15 (App Router, SSG) · Tailwind CSS v4 · Fumadocs · Shiki · `next/font`  
**Ícone Principal:** [`assets/icon.svg`](../assets/icon.svg) · [`assets/icon.png`](../assets/icon.png) — ver *Brand Assets* em [prd-master.md](./prd-master.md)  
**Origem:** `hallmark study` de [pnpm.io](https://pnpm.io/), [puro.dev](https://puro.dev/) e [asccli.sh](https://asccli.sh/) (HTML/CSS + gravação de tela navegando nos três em dark mode).

---

## 1. Introduction / Overview

### O Problema
O `spmx` não tem presença web. Quem chega pelo GitHub não encontra, em uma tela, **o que é**, **como instalar** e **por que acreditar**. Não há documentação navegável fora dos PRDs internos, nem números medidos que sustentem as metas de desempenho (as metas da seção 7 do [prd-spmx-cli.md](./prd-spmx-cli.md) são alvos, não medições).

### A Solução
Um site estático em Next.js com três superfícies que compartilham o mesmo sistema visual:

1. **Landing** — estilo visual do pnpm (dark-first, Inter + JetBrains Mono, destaque laranja, faixas quentes, ritmo alternado), com a objetividade do asc e do puro (uma frase diz o que é, uma linha instala).
2. **Docs** — Fumadocs (MDX, busca local, índice, "Edit on GitHub", `llms.txt`), organizadas como o puro (quick start em cheat sheet) e integradas visualmente como o pnpm (os diagramas da landing reaparecem nas docs).
3. **Benchmarks** — números produzidos por um harness local reproduzível (`bench/`), consumidos pelo site via JSON validado. Nenhum número é escrito à mão na copy.

Princípio: **uma tela para entender, uma linha para instalar, um diagrama para acreditar.**

---

## 2. Goals

- **Clareza imediata:** visitante entende o que o `spmx` faz e copia o comando de instalação sem rolar a página (hero com ≤ 7 palavras + 1 linha de apoio + abas `brew`/`curl`).
- **Prova honesta:** todo número exibido vem de `bench/results/*.json`, com máquina e metodologia visíveis; nenhuma métrica, depoimento ou logo inventado.
- **Docs completas:** toda subcomand do CLI (`Sources/spmx/Commands`) tem página própria; quick start legível em < 1 minuto.
- **SEO e descoberta por agentes:** metadata por página, sitemap, robots, canonical, OG dinâmico, JSON-LD, `llms.txt` / `llms-full.txt`.
- **Performance:** LCP < 1,8 s, CLS ≈ 0, zero JS de highlight no cliente (Shiki em build).
- **Mobile sem quebra:** renderização correta em 320 / 375 / 414 / 768 px, sem scroll horizontal.
- **Identidade própria:** inspirado no pnpm sem parecer clone (matiz laranja-avermelhado do ícone, motivo pixel-art).

---

## 3. Referências Estudadas (resumo do diagnóstico)

### 3.1. pnpm.io — referência visual principal
- **DNA:** `#fff` / dark `#121212`, destaque `#f69220`, superfície creme `#fff8df` (dark: `#2a2210`), Inter 300–800 + JetBrains Mono, tokens semânticos (`--colors-surface-*`, `--colors-text-*`, `--colors-status-*`), dark via `[data-theme=dark]`, DocSearch.
- **Ritmo (vídeo):** container ~1080 px, padding vertical generoso, alternância split (texto + visual) ↔ centralizado (grade/tabela); faixas com tint âmbar em "How it works" e no footer; glow radial atrás do hero.
- **Incorporar:** paleta e tokens, alternância de ritmo, diagrama "single store, linked everywhere", tabela comparativa, CTA final com abas de SO, diagramas reaproveitados nas docs, sidebar com "On this page" + "Edit this page".
- **Evitar:** 11 seções (longo demais), eyebrow em toda seção, terminal com traffic lights falsos (`#ff5f57`), link laranja com contraste ~2,4:1, 9× `transition: all` e ~25 `@keyframes`.

### 3.2. puro.dev — simplicidade de docs
- **DNA:** MkDocs Material (deep-purple, slate), Roboto + Roboto Mono, 3 colunas fixas, densidade uniforme.
- **Incorporar:** aba de instalação pré-selecionada pelo SO, quick start como cheat sheet comentada, diagrama de disco antes/depois.
- **Evitar:** visual genérico sem identidade, ausência de hero/CTA, changelog infinito de "Bug fixes", `robots.txt`/`llms.txt` retornando 403.

### 3.3. asccli.sh — objetividade
- **DNA:** Next.js + Tailwind v4, Inter + Inter Tight, zinc-950, nav em pílula flutuante, hero em coluna estreita centralizada, badge `Latest x.y.z`, 4 stats estruturais, JSON-LD, `llms.txt` 200, OG 1200×630 com alt.
- **Incorporar:** fórmula do título (verbo + objeto, subtítulo de uma linha), instalação rotulada, card de feature com **comando real**, badge de release, stats estruturais verdadeiros ("1 single binary"), FAQ, seção para agentes de IA, kit de SEO.
- **Evitar:** 12 cards idênticos, neutros sem identidade, padding uniforme entre seções, comando de instalação repetido 3×, testimonials raspados do X.

---

## 4. Direção de Design (Hallmark)

| Eixo | Decisão |
| :--- | :--- |
| Gênero | modern-minimal (dev tool) |
| Tema | studied-DNA (pnpm) com destaque derivado do ícone spmx (~`#ea6a38`, convertido para OKLCH no build; tons mais escuros para texto/link ≥ 4,5:1) |
| Modo | dark-first (revisão, OG e screenshots em dark); light via `prefers-color-scheme` + toggle |
| Macroestrutura | Narrative Workflow — instalar → `spmx setup` → `git worktree add` → hidratação via `clonefile` → build |
| Nav | N13 · pílula de busca ⌘K inline |
| Footer | Ft2 · linha única |
| Tipografia | Inter (display/body) + JetBrains Mono (código/labels) via `next/font`; headings sempre roman |
| Assinatura | ícone pixel-art com `image-rendering: pixelated`; divisor em grade de pixels |
| Motion | ≤ 3 primitivas (draw do diagrama, copy-feedback, reveal único); `prefers-reduced-motion` respeitado; nunca `transition: all` |
| Proibido | chrome redesenhado (traffic lights, frames falsos), eyebrows em toda seção (máx. 1–2), grades uniformes de 12 cards, métricas/depoimentos/logos inventados, headings em itálico |

---

## 5. User Stories

### US-001: Scaffold do Site (Next.js + Tailwind v4 + Fumadocs + Tokens)

**Description:** As a maintainer, I want a statically generated Next.js site in `website/` with Tailwind v4 tokens and Fumadocs wired in, so that landing, docs and benchmarks share one design system and one build.

**Acceptance Criteria:**

- [ ] Criar `website/` com Next.js 15 (App Router), TypeScript estrito e geração estática total (sem rotas dinâmicas em runtime).
- [ ] Tailwind v4 com tokens em `@theme` (OKLCH) em `app/globals.css`: `--color-*` (paper, ink, accent, accent-text, surface-warm, border, status), `--font-*`, `--space-*` (escala 4 pt), `--text-*`, `--ease-*`, `--dur-*`, `--radius-*`.
- [ ] Dark e light com contraste AA verificado (texto ≥ 4,5:1, foco ≥ 3:1).
- [ ] `next/font` self-hosting de Inter e JetBrains Mono.
- [ ] Fumadocs configurado (`source.config.ts`, layout de docs, busca local Orama).
- [ ] Ícone copiado de `assets/icon.svg` para `website/public/` por script de pré-build (não versionado em duplicata, conforme regra de Brand Assets).
- [ ] `npm run build` e `npm run lint` passam sem erros.

---

### US-002: Harness de Benchmarks Locais (`bench/`)

**Description:** As a maintainer, I want a reproducible local benchmark harness that measures spmx against vanilla SwiftPM/Xcode, so that every number on the site is real, reproducible and tied to a machine.

**Acceptance Criteria:**

- [ ] Criar `bench/` na raiz com `run.sh` (flags `--quick`, `--scenario <id>`), `fixtures.json`, `lib/reset.sh`, `lib/disk.sh`, `lib/env.sh`, `results/` e `README.md`; alvo `make bench`.
- [ ] Usar **hyperfine** (`--warmup 1 --runs 10 --prepare lib/reset.sh --export-json`); `run.sh` falha com mensagem clara se `hyperfine` não estiver instalado.
- [ ] Fixtures com repositório + commit fixo (nada vendorizado): (1) Swift nativo com macros (`swift-syntax` → `prebuilts`); (2) Xcode com SDK binário pesado via SPM (ex.: Firebase → `artifacts`); (3) Flutter + SPM com plugins Firebase e `pubspec.lock` fixo.
- [ ] A/B via variáveis existentes no CLI: `SPMX_DISABLE`, `SPMX_NO_COMPILE_CACHE` (baseline) e `SPMX_STORE_DIR`, `SPMX_COMPILATION_CACHE_DIR` (isolamento).
- [ ] Cenários implementados:

  | # | Cenário | Baseline vs spmx |
  | :--- | :--- | :--- |
  | S1 | Cold (sem cache algum) — spmx não pode piorar | `-resolvePackageDependencies` com `SPMX_DISABLE=1` vs spmx |
  | S2 | Novo worktree, só cache do SwiftPM quente | mesmo comando nos dois modos |
  | S3 | **Novo worktree, store spmx quente (headline)** | resolução nativa vs `spmx hydrate` |
  | S4 | Disco: 5 worktrees | bytes físicos extras/worktree, nativo vs hidratado |
  | S5 | Overhead de shim (`swift --version`, `flutter --version`) | binário direto vs shim (meta < 5 ms) |
  | S6 | Build limpo no 2º worktree (LLVM CAS) | `SPMX_NO_COMPILE_CACHE=1` vs cache ligado |

- [ ] S1 e S2 marcados `network_dependent: true`; S6 fora do `--quick`.
- [ ] Disco medido em **bytes físicos**: imagem APFS esparsa isolada (`hdiutil create -fs APFS -type SPARSE`) contendo worktrees **e** store; delta de espaço livre do volume (`statfs`/`df -k`) por worktree; imagem desmontada e removida ao final. `du` não é usado para custo físico (conta tamanho lógico de clones).
- [ ] `lib/env.sh` registra chip, RAM, macOS, Xcode, Swift e versão + commit do spmx.
- [ ] Saída normalizada em `bench/results/<data>-<chip>.json` e `bench/results/latest.json` no schema:

  ```json
  {
    "schema": 1,
    "date": "…", "spmx": "<versão+commit>",
    "machine": { "chip": "…", "ram_gb": 0, "macos": "…", "xcode": "…", "swift": "…" },
    "scenarios": [
      { "id": "S3", "fixture": "flutter-firebase", "network_dependent": false,
        "baseline": { "median_s": 0, "min_s": 0, "max_s": 0, "stddev_s": 0, "runs": 10 },
        "spmx":     { "median_s": 0, "min_s": 0, "max_s": 0, "stddev_s": 0, "runs": 10 },
        "disk_bytes": null }
    ]
  }
  ```

- [ ] `bench/README.md` documenta pré-requisitos, como reproduzir e como interpretar resultados.

---

### US-003: Pipeline de Dados de Benchmark para o Site

**Description:** As a maintainer, I want the site to read benchmark numbers only from the validated results JSON, so that copy and measurements can never drift apart.

**Acceptance Criteria:**

- [ ] Script de pré-build copia `bench/results/latest.json` para `website/content/benchmarks/latest.json`.
- [ ] Schema Zod valida o arquivo; **build falha** se o JSON estiver ausente ou inválido.
- [ ] Helpers tipados (`lib/benchmarks.ts`) expõem headline (S3), disco (S4), shim (S5) e metadados da máquina.
- [ ] Nenhum número de desempenho aparece hardcoded em componentes ou MDX (verificável por grep no CI).
- [ ] Resultados que não atingem a meta do PRD do CLI continuam publicados em `/benchmarks`, mas não são promovidos a headline.

---

### US-004: Landing Page

**Description:** As a visitor, I want to understand what spmx does, install it, and see proof in one scroll, so that I can decide to try it in under a minute.

**Acceptance Criteria:**

- [ ] Seções em ordem, com ritmo alternado (split ↔ centralizado) e faixa quente apenas em "Como funciona" e no footer:
  1. **Hero** (split): ícone pixel-art, título ≤ 7 palavras, uma linha de apoio, badge `Latest x.y.z` (release do GitHub no build), abas `brew`/`curl` com detecção de SO e botão copiar, "Get started" + GitHub; à direita, `<pre>` com saída real de `spmx hydrate` (borda hairline, sem traffic lights).
  2. **Problema** (3 linhas): novo worktree → novo hash de `DerivedData` → re-download e GBs duplicados.
  3. **Como funciona** (split, faixa quente): `StoreDiagram` (US-005) + 3–4 bullets.
  4. **Workflow em 4 passos**: `setup` → `git worktree add` → hidratação automática → `flutter run` / `xcodebuild`, cada passo com comando real.
  5. **Stats + benchmark**: stats estruturais verdadeiros (binário universal, arm64 + x86_64, zero-config, tamanho do binário conferido no release) + barras S3/S4/S5 lidas do JSON, com máquina em letra pequena.
  6. **Features** (≤ 6, tamanhos variados): store CAS, shims zero-config, LLVM CAS, Git hooks opt-in, Flutter, `doctor` — cada uma com comando e link para doc.
  7. **Feito para agentes de IA**: worktrees paralelos, segurança concorrente, `llms.txt`.
  8. **Comparação** sem spmx vs com spmx.
  9. **FAQ** (5–6): Xcode GUI, puro/fvm, Linux, CI, uninstall, segurança do store.
  10. **CTA final** (instalação + "Read the docs") e footer Ft2.
- [ ] Máximo de 1–2 eyebrows na página.
- [ ] Todos os elementos interativos com os 8 estados (default, hover, `:focus-visible`, active, disabled, loading, error, success onde aplicável).
- [ ] Copy em inglês; nenhum depoimento, logo ou métrica inventado.
- [ ] Sem scroll horizontal em 320 / 375 / 414 / 768 px; `overflow-x: clip` em `html` e `body`.

---

### US-005: Componente `StoreDiagram` Compartilhado

**Description:** As a visitor, I want a clear diagram of the global store being cloned into multiple worktrees, so that I understand why spmx is fast and disk-cheap.

**Acceptance Criteria:**

- [ ] SVG feito à mão: `~/.spmx/store` (centro) → `clonefile()` → N worktrees (`SourcePackages/checkouts`, `artifacts`, `prebuilts`).
- [ ] Uma única animação de draw das conexões; estático com `prefers-reduced-motion: reduce`.
- [ ] Cores apenas via tokens; legível em dark e light.
- [ ] Reutilizado na landing e em `docs/concepts/global-store` (MDX).
- [ ] Texto alternativo/descrição acessível do diagrama.

---

### US-006: Documentação (Fumadocs)

**Description:** As a user, I want navigable docs covering install, concepts, every command and common guides, so that I can adopt spmx without reading source code.

**Acceptance Criteria:**

- [ ] Arquitetura de informação:
  - **Getting Started:** Installation, Quick Start (cheat sheet comentada estilo puro), Uninstall.
  - **Concepts:** Global Store, APFS `clonefile`, Shims, LLVM Compilation Cache, Worktrees.
  - **Commands:** uma página por comando — `setup`, `hydrate`/`install`, `harvest`, `migrate`, `store`, `status`, `doctor`, `hooks`, `derived-data-path`, `uninstall` — com flags extraídas de `Sources/spmx/Commands`.
  - **Guides:** Flutter + SPM, Xcode nativo, CI, AI agents & parallel worktrees, interop com puro/fvm, Reproduce the benchmarks.
  - **Troubleshooting**, **FAQ**, **Changelog** (gerado das releases do GitHub, agrupado por versão maior).
- [ ] Conteúdo escrito a partir dos PRDs, reescrito para usuário final (não copiado literalmente).
- [ ] "Edit on GitHub", "On this page", busca ⌘K e botão "Copy as Markdown" por página.
- [ ] Blocos de código com Shiki em build e botão copiar; sem chrome falso.

---

### US-007: Página `/benchmarks`

**Description:** As a skeptical developer, I want to see methodology, raw data and how to reproduce, so that I can trust the numbers on the landing.

**Acceptance Criteria:**

- [ ] Barras em SVG estático para S1–S6 (sem biblioteca de charts), mediana + min/max.
- [ ] Bloco de metodologia: fixtures e commits, máquina, runs, warmup, como o disco físico é medido.
- [ ] S1/S2 identificados como dependentes de rede.
- [ ] Link para o JSON bruto e para o guia "Reproduce the benchmarks".

---

### US-008: Kit de SEO e Descoberta por Agentes

**Description:** As a maintainer, I want complete technical SEO and agent-readable outputs, so that spmx ranks for its problem space and AI tools can read the docs.

**Acceptance Criteria:**

- [ ] Metadata API: `metadataBase`, template de título, `generateMetadata` por página de doc, canonical em todas as rotas.
- [ ] `app/sitemap.ts` e `app/robots.ts` (robots não bloqueia crawlers legítimos nem `llms.txt`).
- [ ] `opengraph-image.tsx` (next/og) gerando OG 1200×630 por página com ícone + título + alt; se exibir número, lê do JSON de benchmarks.
- [ ] JSON-LD (`lib/jsonld.ts`): `SoftwareApplication` (`operatingSystem: macOS`, `applicationCategory: DeveloperApplication`, `offers` gratuito), `WebSite` com `SearchAction`, `BreadcrumbList` nas docs.
- [ ] `llms.txt` e `llms-full.txt` gerados do MDX.
- [ ] Idioma principal inglês (`<html lang="en">`); estrutura preparada para `pt-BR` futuro com `hreflang`.

---

### US-009: Qualidade — Lighthouse CI, Acessibilidade e Mobile

**Description:** As a maintainer, I want automated quality gates, so that performance, accessibility and SEO don't regress.

**Acceptance Criteria:**

- [ ] Lighthouse CI (ou unlighthouse) no GitHub Actions para landing, uma página de doc e `/benchmarks`, com budget: LCP < 1,8 s, CLS ≤ 0,05, Performance/Accessibility/SEO ≥ 95.
- [ ] Verificação de contraste dos tokens em dark e light.
- [ ] Navegação completa por teclado; foco visível sem animação.
- [ ] Teste visual em 320 / 375 / 414 / 768 px sem scroll horizontal nem links/botões quebrando em duas linhas.
- [ ] Job opcional `bench --quick` (S3 + S5) em PRs que alteram `Sources/`, apenas como alerta de regressão (não bloqueia, não alimenta o site).

---

### US-010: Deploy e Domínio

**Description:** As a maintainer, I want the site deployed on a custom domain with previews, so that it's publicly reachable and every change is reviewable.

**Acceptance Criteria:**

- [ ] Deploy estático (Vercel ou Cloudflare Pages) a partir de `website/`, com preview por PR.
- [ ] Domínio definido (ver Open Questions) e configurado com HTTPS.
- [ ] Links do `install.sh` e da fórmula Homebrew apontando para os endereços oficiais.
- [ ] Placeholder `ProjectsUsing` preparado (desativado) para quando existirem projetos reais usando spmx.

---

## 6. Functional Requirements

- **FR-1:** O site deve ser 100% estático (SSG), sem servidor em runtime.
- **FR-2:** Todo número de desempenho exibido deve vir de `website/content/benchmarks/latest.json`, validado por schema no build.
- **FR-3:** O comando de instalação deve aparecer no hero e no CTA final (não mais que 2×), com abas `brew`/`curl` e detecção de SO.
- **FR-4:** Cada subcomando do CLI deve ter uma página de documentação.
- **FR-5:** Todas as cores e fontes devem referenciar tokens nomeados; nenhum valor de cor inline.
- **FR-6:** O site deve funcionar sem JavaScript para leitura de conteúdo (busca, copy e toggle de tema podem exigir JS).
- **FR-7:** `bench/run.sh` deve produzir JSON no schema `1` e falhar explicitamente quando pré-requisitos estiverem ausentes.
- **FR-8:** O ícone deve ser sempre derivado de `assets/icon.svg`, renderizado com `image-rendering: pixelated` quando raster.

---

## 7. Non-Goals (Out of Scope na v1)

- Blog, newsletter, contas de usuário ou analytics invasivo.
- Seletor de versão nas docs (Fumadocs suporta; habilitar quando existir v2 do CLI).
- Versão `pt-BR` do conteúdo (estrutura preparada, conteúdo depois).
- Parede de depoimentos, Wall of Apps / logos de usuários e sponsors (somente quando houver dados reais).
- Benchmarks executados em CI para alimentar o site (runners macOS são ruidosos).
- Linux (o CLI é macOS-only na v1).

---

## 8. Technical Considerations

### 8.1. Por que Fumadocs em vez de Nextra/Docusaurus
Nativo do App Router, MDX com componentes React (permite reusar `StoreDiagram` e `CommandCard`), busca local Orama sem Algolia, geração de `llms.txt` e flexibilidade total de layout para manter o sistema visual da landing.

### 8.2. Por que medir disco por delta de volume APFS
`clonefile()` cria cópias que compartilham blocos; `du` reporta o tamanho lógico e superestima o custo. Medir o espaço livre de um volume APFS isolado antes/depois de cada worktree captura o custo físico real. Store e worktrees precisam estar no mesmo volume (requisito do `clonefile`), por isso `SPMX_STORE_DIR` aponta para dentro da imagem.

### 8.3. Diferenciação do pnpm
O logo do pnpm também é pixel-art laranja. Para não parecer derivado: matiz deslocado para o laranja-avermelhado do ícone spmx (~H 40 vs ~H 60), motivo de grade de pixels como assinatura, `<pre>` real no lugar de terminal com traffic lights, e menos seções.

### 8.4. Estrutura de arquivos prevista (todos novos)

```
website/
  app/(home)/page.tsx            app/docs/[[...slug]]/page.tsx
  app/benchmarks/page.tsx        app/layout.tsx  app/globals.css
  app/sitemap.ts  app/robots.ts  app/opengraph-image.tsx
  app/llms.txt/route.ts          app/llms-full.txt/route.ts
  components/{InstallTabs,StoreDiagram,CommandCard,BenchBars,Faq,SearchPill}.tsx
  content/docs/**/*.mdx          content/benchmarks/latest.json (gerado)
  lib/{jsonld,benchmarks}.ts     source.config.ts
bench/
  run.sh  fixtures.json  lib/{reset,disk,env}.sh  results/  README.md
```

### 8.5. Fases e dependências

1. **Scaffold** (US-001).
2. **Benchmarks locais** (US-002, US-003) — paralelo à fase 1.
3. **Landing** (US-004, US-005) — consome o JSON da fase 2.
4. **Docs + `/benchmarks`** (US-006, US-007).
5. **SEO + qualidade** (US-008, US-009).
6. **Deploy** (US-010).

---

## 9. Success Metrics

- Lighthouse ≥ 95 em Performance, Accessibility e SEO nas três rotas monitoradas.
- LCP < 1,8 s e CLS ≤ 0,05 (campo e laboratório).
- 100% dos subcomandos do CLI documentados.
- 0 números de desempenho hardcoded (verificação por grep no CI).
- Benchmarks reproduzíveis: segunda execução em outra máquina produz JSON válido no mesmo schema.
- Páginas indexadas no Google Search Console após o deploy (sitemap aceito sem erros).

---

## 10. Open Questions

1. **Domínio e GitHub org:** ainda indefinidos (mesma Open Question #1 do [prd-spmx-cli.md](./prd-spmx-cli.md)); bloqueiam US-010 e os links do instalador.
2. **Lançamento sem benchmarks:** publicar o site antes da fase 2 terminar (stats estruturais apenas) ou aguardar os números?
3. **Fixtures exatos:** quais repositórios e commits públicos representam melhor os três perfis (macros, SDK binário, Flutter + Firebase)?
4. **Idioma:** confirmar inglês apenas na v1.
5. **Hospedagem:** Vercel ou Cloudflare Pages?
