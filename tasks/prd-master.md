# PRD Master Tracker — spmx

Living tracker for PRDs in `~/projects/spmx`.

<p align="center"><img src="../assets/icon.png" alt="spmx icon" width="96"></p>

---

## Brand Assets

O **ícone principal** do `spmx` é a caixa laranja *pixel-art* (isométrica, aberta, com a "pena/chama" saindo do topo). Esta é a **fonte única de verdade** para qualquer uso de identidade visual do projeto:

| Arquivo | Formato | Dimensões | Uso recomendado |
| :--- | :--- | :--- | :--- |
| [`assets/icon.svg`](../assets/icon.svg) | SVG vetorial (`crispEdges`, `viewBox` 41×48, gradiente laranja, contorno branco de 1px) | escalável (base 410×480) | **Fonte primária.** README, site, documentação, Homebrew tap, qualquer contexto que aceite vetor. |
| [`assets/icon.png`](../assets/icon.png) | PNG RGBA com transparência | 410×480 | Raster derivado do SVG. Social preview do GitHub, avatar, release notes, OG image do site, contextos que não aceitam SVG. |
| [`assets/favicons/`](../assets/favicons/) | `favicon.ico` (16/32/48), PNG 16×16 e 32×32, `apple-touch-icon.png` 180×180, `android-chrome-*.png` 192×192 e 512×512 | quadrados | Favicons e ícones do web manifest do site. Copiados para `website/public/` pelo pré-build; o favicon SVG é o próprio `icon.svg`. |

Regras:
- Sempre referenciar `assets/icon.svg` / `assets/icon.png` / `assets/favicons/` por caminho relativo; **não duplicar** nem recolorir o ícone em outros diretórios.
- Em escala, manter proporção (41:48) e renderizar com `image-rendering: pixelated` (PNG) para preservar as bordas da pixel-art.
- Ao alterar o ícone, atualizar **o SVG, o PNG e os favicons juntos** (PNG e favicons são exportados do SVG).

---

## Active & Planned PRDs

| PRD | Status | Stories | File |
| :--- | :--- | :--- | :--- |
| **spmx — Performant Swift Package Manager (CLI)** | Implemented (v1) | `US-001` – `US-009` | [prd-spmx-cli.md](./prd-spmx-cli.md) |
| **spmx — Landing Page + Docs + Benchmarks** | Implemented (`US-001` – `US-010`) | `US-001` – `US-010` | [prd-site.md](./prd-site.md) |
| **spmx — Store Global na Máquina Toda & Pivot GTM** | Planned (Ready for implementation) | `US-001` – `US-007` | [prd-machine-wide-store.md](./prd-machine-wide-store.md) |

---

## User Stories Summary (`prd-machine-wide-store.md`)

- [ ] **US-001:** Indexação por Versão Semântica e Mapeamento Multi-Projeto no `GlobalStore`
- [ ] **US-002:** Cache de `SourcePackages/repositories/` (Bare Git Repos) e Hidratação Parcial entre Projetos
- [ ] **US-003:** Guarda contra Checkout Sujo no `harvest` e Pré-Hidratação Cross-Project no Flutter
- [ ] **US-004:** Comandos `spmx link [path]` e `spmx unlink [path]` (Opt-Out por Projeto e Varredura com Confirmação)
- [ ] **US-005:** Relatório de Versões e Economia de Espaço por Projeto e Global (`status`, `store list`, `store status`)
- [ ] **US-006:** Reescrita do `README.md` e Documentação Técnica com as Skills do `gtm-cofounder`
- [ ] **US-007:** Pivot da Landing Page (`spmx.io`), `StoreDiagram` e `CliSample` com `the-homepage` (`gtm-cofounder`)

---

## User Stories Summary (`prd-spmx-cli.md`)

- [x] **US-001:** Scaffold do Projeto Open-Source em Swift e Cálculo Determinístico do `DerivedData`
- [x] **US-002:** Detecção de Tipo de Projeto e Parser de `Package.resolved` (v1, v2 e v3) e `workspace-state.json` (`artifacts` + `prebuilts`)
- [x] **US-003:** Content-Addressable Store Global (`~/.spmx/store`) com `checkouts`, `artifacts`, `prebuilts`, Hash de Toolchain e Engine APFS `clonefile()`
- [x] **US-004:** Hidratação (`hydrate`) e Colheita (`harvest`) do `SourcePackages` (`checkouts`, `artifacts`, `prebuilts`) e `workspace-state.json`
- [x] **US-005:** Integração Específica com Projetos Flutter (`FlutterGeneratedPluginSwiftPackage`)
- [x] **US-006:** Sistema de Shims Transparentes no `PATH` + Cache de Compilação Nativo (LLVM CAS) no `xcodebuild`/`swift`
- [x] **US-007:** Git Hooks Opt-in para Worktrees (`spmx hooks enable | disable | status`)
- [x] **US-008:** Comandos de Gerenciamento, Inspeção e Diagnóstico (`store`, `status`, `doctor`) incluindo `~/.spmx/compilation-cache`
- [x] **US-009:** Instalador One-Liner (`curl | sh`) e Distribuição via Homebrew

---

## User Stories Summary (`prd-site.md`)

- [x] **US-001:** Scaffold do Site (Next.js + Tailwind v4 + Fumadocs + Tokens)
- [x] **US-002:** Harness de Benchmarks Locais (`bench/`)
- [x] **US-003:** Pipeline de Dados de Benchmark para o Site
- [x] **US-004:** Landing Page
- [x] **US-005:** Componente `StoreDiagram` Compartilhado
- [x] **US-006:** Documentação (Fumadocs)
- [x] **US-007:** Página `/benchmarks`
- [x] **US-008:** Kit de SEO e Descoberta por Agentes
- [x] **US-009:** Qualidade — Lighthouse CI, Acessibilidade e Mobile
- [x] **US-010:** Deploy e Domínio

---

## Pending Tasks (CI/CD, Release, Infra & Segurança)

- [x] **GitHub Actions — Deploy do Site (`website/`):** Configurar workflow no GitHub Actions para fazer deploy do site quando necessário (ex.: alterações em `website/` na `main` e disparo manual via `workflow_dispatch`).
- [x] **GitHub Actions — Nova Release (Versionamento):** Configurar action (integrada ao [`.github/workflows/release.yml`](../.github/workflows/release.yml)) para gerar uma nova release via `workflow_dispatch`:
  - **Default:** `patch` update automático com base na última tag semver (`vX.Y.Z` → `vX.Y.(Z+1)`).
  - **Opcional:** campo de entrada para definir manualmente a nova versão (ex.: `vX.Y.Z` ou tipo de bump) quando necessário.
- [x] **URL Curta de Instalação (`get.spmx.io`) — Hostinger, Cloudflare e Código:** Substituir a URL longa do `curl` (`raw.githubusercontent.com/LuisRibeiroo/spmx/main/scripts/install.sh`) por `https://get.spmx.io`:
  1. **Hostinger (Domínio & Nameservers):** Verificar domínio `spmx.io` ativo na Hostinger e apontar os nameservers para o Cloudflare (ou, se mantiver DNS na Hostinger, criar `CNAME` `get` para o endpoint no Cloudflare com SSL ativo).
  2. **Cloudflare (DNS, SSL e Rota `get.spmx.io`):**
     - Adicionar a zona `spmx.io` no Cloudflare, definir SSL/TLS como **Full (strict)** e ativar **Always Use HTTPS**.
     - Criar o registro DNS proxied (nuvem laranja) para `get.spmx.io` (ex.: `A 192.0.2.1` placeholder proxied ou `CNAME` para o Pages/Worker).
     - Configurar **Cloudflare Worker** na rota `get.spmx.io/*` para servir `scripts/install.sh` com `200 OK` e `Content-Type: text/plain; charset=utf-8` (ou *Redirect Rule* para `https://raw.githubusercontent.com/LuisRibeiroo/spmx/main/scripts/install.sh` / `https://spmx.io/install.sh`).
     - Testar com `curl -fsSL https://get.spmx.io | head -n 20`.
  3. **Atualização no Repositório:** Trocar a URL do `curl` para `https://get.spmx.io` em [`website/lib/repo.ts`](../website/lib/repo.ts), [`website/content/docs/getting-started/installation.mdx`](../website/content/docs/getting-started/installation.mdx), [`website/content/docs/guides/ci.mdx`](../website/content/docs/guides/ci.mdx), [`README.md`](../README.md) e [`scripts/install.sh`](../scripts/install.sh), e validar o build com `make site`.
- [x] **Governança e Proteção do Repositório (GitHub):** Validar as configurações de acesso e *branch protection* / *rulesets* da `main` para garantir que apenas o mantenedor (`LuisRibeiroo`) possui acesso de escrita e que PRs exijam aprovação do mantenedor (ex.: `CODEOWNERS` + *Require review from Code Owners*) para serem mergeadas.
- [x] **Issue Templates (`.github/ISSUE_TEMPLATE/`):** Criar templates de issue padronizados (ex.: *Bug report*, *Feature request* e `config.yml`).
- [x] **Auditoria de Segredos e Arquivos Privados:** Varrer o repositório (working tree e histórico Git) para garantir que nenhuma chave, token, credencial ou arquivo privado (como `.env`) esteja commitado, e reforçar o `.gitignore` se necessário.
- [ ] **SEO & OG Images para Redes Sociais (`website/`):** Melhorar o SEO do site e adicionar/aprimorar OG images (Open Graph, Twitter/X `summary_large_image` e demais redes sociais), utilizando o ícone/logo oficial do app ([`assets/icon.svg`](../assets/icon.svg) / [`assets/icon.png`](../assets/icon.png)) como elemento principal da imagem.
- [ ] **Auditoria de Segurança (Skill de Segurança):** Executar análise de segurança no repositório (CLI Swift, scripts `install.sh`, workflows do GitHub Actions, Cloudflare Worker e `website/`) para identificar e corrigir possíveis vulnerabilidades.

---

## Roadmap v2 (Pós-MVP)

- **Proxy Binary Cache (`.xcframework` estilo `xccache`) no `FlutterGeneratedPluginSwiftPackage`:** Mantido fora da v1 devido aos riscos de ciclo de vida com `flutter_tools` (`ephemeral/`), acoplamento de slices do `Flutter.xcframework`, quebra de `Bundle.module`/`PrivacyInfo.xcprivacy` e símbolos duplicados; será avaliado na v2 apenas caso o Cache de Compilação LLVM CAS nativo da v1 não seja suficiente.
- **Suporte Linux / `spmx open`:** Extensão opcional para Linux (`FICLONE`/hardlinks) e comando dedicado para abrir Xcode GUI pré-hidratado.
- **Comando de instalação curto, sem o nome do usuário (site):** Servir o instalador pelo próprio site (`curl -fsSL https://<domínio>/install | sh`) em vez da URL `raw.githubusercontent.com/<usuário>/spmx/...`. O build do `website/` copiaria `scripts/install.sh` para `public/` e a landing/docs passariam a usar `SITE_URL` no comando (com fallback para a URL do GitHub quando a variável não estiver definida). Depende da definição do domínio (Open Question #1 de [prd-site.md](./prd-site.md)). Para o Homebrew, remover o nome do usuário exige uma organização no GitHub com repositório `homebrew-tap` (`brew install <org>/tap/spmx`) ou a entrada no `homebrew-core`, que exige notoriedade do projeto.

---

## Open Questions

1. **GitHub Org / Repositório:** Definir URL oficial (`github.com/<org>/spmx`) para `install.sh` e Homebrew Tap.
2. **Xcode GUI:** Avaliar comando `spmx open` (ou watcher) na v2 além do hook `post-checkout` opt-in.
3. **Interoperabilidade com `puro flutter ...`:** Validar no `spmx doctor` se `puro flutter` dispara apenas o shim `xcodebuild` ou se vale suporte dedicado.
4. **TTL do `spmx store prune`:** Definir expiração padrão de pacotes órfãos e entradas do `~/.spmx/compilation-cache` (sugestão: 30 dias).
