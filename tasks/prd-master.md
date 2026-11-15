# PRD Master Tracker — pspm

Living tracker for PRDs in `~/projects/pspm`.

<p align="center"><img src="../assets/icon.png" alt="pspm icon" width="96"></p>

---

## Brand Assets

O **ícone principal** do `pspm` é a caixa laranja *pixel-art* (isométrica, aberta, com a "pena/chama" saindo do topo). Esta é a **fonte única de verdade** para qualquer uso de identidade visual do projeto:

| Arquivo | Formato | Dimensões | Uso recomendado |
| :--- | :--- | :--- | :--- |
| [`assets/icon.svg`](../assets/icon.svg) | SVG vetorial (`crispEdges`, `viewBox` 41×47, gradiente laranja) | escalável (base 410×470) | **Fonte primária.** README, site, documentação, Homebrew tap, qualquer contexto que aceite vetor. |
| [`assets/icon.png`](../assets/icon.png) | PNG RGBA com transparência | 820×940 | Raster derivado do SVG. Social preview do GitHub, avatar, release notes, contextos que não aceitam SVG. |

Regras:
- Sempre referenciar `assets/icon.svg` / `assets/icon.png` por caminho relativo; **não duplicar** nem recolorir o ícone em outros diretórios.
- Em escala, manter proporção (41:47) e renderizar com `image-rendering: pixelated` (PNG) para preservar as bordas da pixel-art.
- Ao alterar o ícone, atualizar **os dois arquivos juntos** (PNG é exportado do SVG).

---

## Active & Planned PRDs

| PRD | Status | Stories | File |
| :--- | :--- | :--- | :--- |
| **pspm — Performant Swift Package Manager (CLI)** | Implemented (v1) | `US-001` – `US-009` | [prd-pspm-cli.md](./prd-pspm-cli.md) |

---

## User Stories Summary (`prd-pspm-cli.md`)

- [x] **US-001:** Scaffold do Projeto Open-Source em Swift e Cálculo Determinístico do `DerivedData`
- [x] **US-002:** Detecção de Tipo de Projeto e Parser de `Package.resolved` (v1, v2 e v3) e `workspace-state.json` (`artifacts` + `prebuilts`)
- [x] **US-003:** Content-Addressable Store Global (`~/.pspm/store`) com `checkouts`, `artifacts`, `prebuilts`, Hash de Toolchain e Engine APFS `clonefile()`
- [x] **US-004:** Hidratação (`hydrate`) e Colheita (`harvest`) do `SourcePackages` (`checkouts`, `artifacts`, `prebuilts`) e `workspace-state.json`
- [x] **US-005:** Integração Específica com Projetos Flutter (`FlutterGeneratedPluginSwiftPackage`)
- [x] **US-006:** Sistema de Shims Transparentes no `PATH` + Cache de Compilação Nativo (LLVM CAS) no `xcodebuild`/`swift`
- [x] **US-007:** Git Hooks Opt-in para Worktrees (`pspm hooks enable | disable | status`)
- [x] **US-008:** Comandos de Gerenciamento, Inspeção e Diagnóstico (`store`, `status`, `doctor`) incluindo `~/.pspm/compilation-cache`
- [x] **US-009:** Instalador One-Liner (`curl | sh`) e Distribuição via Homebrew

---

## Roadmap v2 (Pós-MVP)

- **Proxy Binary Cache (`.xcframework` estilo `xccache`) no `FlutterGeneratedPluginSwiftPackage`:** Mantido fora da v1 devido aos riscos de ciclo de vida com `flutter_tools` (`ephemeral/`), acoplamento de slices do `Flutter.xcframework`, quebra de `Bundle.module`/`PrivacyInfo.xcprivacy` e símbolos duplicados; será avaliado na v2 apenas caso o Cache de Compilação LLVM CAS nativo da v1 não seja suficiente.
- **Suporte Linux / `pspm open`:** Extensão opcional para Linux (`FICLONE`/hardlinks) e comando dedicado para abrir Xcode GUI pré-hidratado.

---

## Open Questions

1. **GitHub Org / Repositório:** Definir URL oficial (`github.com/<org>/pspm`) para `install.sh` e Homebrew Tap.
2. **Xcode GUI:** Avaliar comando `pspm open` (ou watcher) na v2 além do hook `post-checkout` opt-in.
3. **Interoperabilidade com `puro flutter ...`:** Validar no `pspm doctor` se `puro flutter` dispara apenas o shim `xcodebuild` ou se vale suporte dedicado.
4. **TTL do `pspm store prune`:** Definir expiração padrão de pacotes órfãos e entradas do `~/.pspm/compilation-cache` (sugestão: 30 dias).
