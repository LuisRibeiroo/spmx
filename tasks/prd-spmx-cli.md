# PRD: spmx — Performant Swift Package Manager (CLI)

**Versão:** 1.0  
**Status:** Draft (Pronto para Implementação)  
**Repositório Alvo:** `~/projects/spmx` (Open Source)  
**Licença Sugerida:** MIT ou Apache 2.0  
**Ícone Principal:** [`assets/icon.svg`](../assets/icon.svg) (vetor) · [`assets/icon.png`](../assets/icon.png) (410×480) — ver *Brand Assets* em [prd-master.md](./prd-master.md)  

---

## 1. Introduction / Overview

O **`spmx`** (*Performant Swift Package Manager*) é uma CLI open-source para macOS projetada para funcionar como um gerenciador e acelerador de cache de dependências do **Swift Package Manager (SPM)** — seguindo a filosofia de arquitetura do **pnpm** (Content-Addressable Store compartilhado) e a ergonomia de instalação e shims do **puro** (gerenciador de versões do Flutter).

### O Problema
Ao utilizar múltiplos **Git worktrees** (para desenvolvimento paralelo em branches ou múltiplos agentes de IA trabalhando simultaneamente) em projetos **Flutter com SPM** ou projetos **Swift/Xcode nativos**, cada worktree nasce em um caminho absoluto distinto no disco. Por padrão:
1. O Xcode calcula o caminho de `DerivedData/<Nome>-<hash>` a partir do **caminho absoluto** do `.xcworkspace`/`.xcodeproj`. Um novo worktree gera um novo hash e encontra um diretório `SourcePackages/` vazio.
2. Apesar de o SwiftPM possuir um cache de repositórios Git em `~/Library/Caches/org.swift.swiftpm/repositories`, cada worktree ainda executa resolução de grafo de dependências, extração de `checkouts/`, download de `prebuilts/` (macros como `swift-syntax`) e download/descompactação de `artifacts/` pesados (`binaryTarget` / `.xcframework` de SDKs como Firebase, Google Ads, WebRTC), consumindo vários minutos de rede/CPU e duplicando gigabytes no SSD.
3. No Flutter com SPM, o pacote agregador `FlutterGeneratedPluginSwiftPackage` fica em `ios/Flutter/ephemeral/` (ignorado pelo Git), exigindo regeneração e nova resolução do Xcode em todo worktree recém-criado.

### A Solução
O `spmx`, implementado em **Swift** como um binário universal (`arm64` + `x86_64`), mantém um **Store Global (`~/.spmx/store`)** com todos os `checkouts`, `artifacts` e `prebuilts` já baixados e os materializa instantaneamente no `DerivedData/.../SourcePackages` (ou `.build/`) de qualquer worktree utilizando a syscall nativa **APFS Copy-on-Write (`clonefile`)** do macOS — resultando em cópias reais isoladas para o Xcode com **~0 bytes adicionais em disco** e tempo de restauração na casa dos milissegundos. Complementarmente, o shim ativa o **Cache de Compilação nativo (LLVM CAS)** do Xcode 16+ / Swift 6 apontando para `~/.spmx/compilation-cache`, permitindo reutilizar objetos compilados entre worktrees sem modificar arquivos do projeto.

Para oferecer experiência **Zero-Config**, o `spmx` instala **shims no `PATH`** por padrão (`flutter`, `xcodebuild`, `swift`) e disponibiliza **Git Hooks (`post-checkout`) opcionais** (desativados por padrão, com aviso informativo na instalação).

---

## 2. Goals

- **Velocidade em Worktrees:** Reduzir o tempo de preparação/resolução de dependências SPM em novos Git worktrees em **> 90%** (de minutos de download/extração para **< 500 ms** em cache quente) e reaproveitar artefatos de compilação via LLVM CAS nativo.
- **Eficiência de Disco:** Reduzir o espaço incremental em disco ocupado por `SourcePackages/checkouts`, `artifacts` e `prebuilts` em worktrees adicionais para **~0 bytes físicos extras** via APFS Copy-on-Write (`clonefile()`).
- **Experiência Zero-Config:** Permitir que projetos Flutter e Swift existentes ou recém-criados utilizem o cache global automaticamente após a instalação, via shims transparentes no `PATH`, com overhead de inicialização **< 5 ms**.
- **Instalação Simples e Global:** Permitir instalação global em um único comando via `curl ... | sh` ou `brew install`.
- **Suporte Dual na v1:** Atender tanto projetos **Flutter (iOS/macOS com SwiftPM)** quanto projetos **Swift/Xcode nativos** (`.xcworkspace`, `.xcodeproj`, `Package.swift`).
- **Segurança Concorrente:** Suportar múltiplos terminais/worktrees/agentes rodando builds em paralelo sem corromper o store global ou o `workspace-state.json`.

---

## 3. User Stories

### US-001: Scaffold do Projeto Open-Source em Swift e Cálculo Determinístico do `DerivedData`

**Description:** As a developer, I want `spmx` to be structured as a clean Swift Package and deterministically compute the exact Xcode `DerivedData/<Name>-<28_chars_hash>` directory path for any `.xcodeproj` or `.xcworkspace`, so that `spmx` can prepare `SourcePackages` before Xcode or `xcodebuild` ever opens the project.

**Acceptance Criteria:**

- [x] Criar pacote Swift modular em `~/projects/spmx` com `Package.swift`, biblioteca `SPMXCore`, executável `spmx` (usando `swift-argument-parser`) e target de testes `SPMXCoreTests`.
- [x] Implementar o algoritmo determinístico do Xcode para o sufixo de 28 caracteres: MD5 dos bytes UTF-8 do caminho absoluto canônico do `.xcworkspace`/`.xcodeproj`, convertido em dois inteiros `UInt64` big-endian e codificado em 28 letras minúsculas (`a`–`z`) em base 26.
- [x] Respeitar a configuração `IDECustomDerivedDataLocation` do domínio `com.apple.dt.Xcode` (via `UserDefaults` / `defaults`) e o campo `DerivedDataLocation` em `WorkspaceSettings.xcsettings` quando presentes, usando `~/Library/Developer/Xcode/DerivedData` como padrão.
- [x] Expor o comando `spmx derived-data-path [caminho]` imprimindo o path exato calculado.
- [x] Testes unitários e de integração validando que o path gerado corresponde 100% ao `BUILD_DIR`/`SYMROOT` retornado pelo `xcodebuild -showBuildSettings` real no macOS.
- [x] `swift build` e `swift test` passam sem erros ou warnings.

---

### US-002: Detecção de Tipo de Projeto e Parser de `Package.resolved` (v1, v2 e v3)

**Description:** As a developer, I want `spmx` to automatically detect whether the current workspace is a Flutter project (iOS/macOS with SPM), an Xcode project/workspace, or a pure SwiftPM package, and parse all pinned dependencies cleanly.

**Acceptance Criteria:**

- [x] Detectar automaticamente a raiz e o tipo de projeto a partir do diretório atual (ou via flag `--project`/`--workspace`):
  - **Flutter:** presença de `pubspec.yaml` com `ios/Runner.xcworkspace` e/ou `macos/Runner.xcworkspace`.
  - **Xcode:** presença de `*.xcworkspace` (prioritário) ou `*.xcodeproj`.
  - **SwiftPM puro:** presença de `Package.swift`.
- [x] Localizar `Package.resolved` nos caminhos padrão (`<workspace>/xcshareddata/swiftpm/Package.resolved`, `<project>/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`, ou `./Package.resolved`).
- [x] Fazer parse dos schemas `Package.resolved` versão `1`, `2` e `3` preservando `identity`, `kind` (`remoteSourceControl`, `registry`, `localSourceControl`), `location`, `revision` (commit SHA), `version` e `branch`.
- [x] Fazer parse de `workspace-state.json` para identificar `artifacts` (`binaryTarget` / `.xcframework`, com `packageRef`, `targetName`, `checksum` e URL/path de origem) e `prebuilts` (binários pré-compilados de Swift Macros como `swift-syntax` presentes em `SourcePackages/prebuilts/`).
- [x] Testes unitários cobrindo fixtures reais de `Package.resolved` v1, v2, v3, `workspace-state.json` com `artifacts` + `prebuilts` e estrutura de projeto Flutter + Xcode + SwiftPM puro.
- [x] `swift build` e `swift test` passam.

---

### US-003: Content-Addressable Store Global (`~/.spmx/store`) e Engine APFS `clonefile()`

**Description:** As a macOS developer, I want `spmx` to store downloaded checkouts, binary XCFramework artifacts, and SwiftPM prebuilt macros once in a global store (keyed by toolchain version where appropriate) and clone them into project directories using APFS Copy-on-Write (`clonefile`), so that multiple worktrees consume ~0 extra SSD space.

**Acceptance Criteria:**

- [x] Implementar wrapper seguro em Swift chamando `<sys/clonefile.h>` (`clonefile(src, dst, 0)`), com staging atômico (clona para path temporário no mesmo diretório pai e move/substitui atomicamente).
- [x] Implementar fallback automático para cópia recursiva padrão (`FileManager.copyItem`) caso `clonefile` retorne `ENOTSUP` (volume não-APFS) ou `EXDEV` (store e `DerivedData` em volumes distintos), registrando aviso em modo verbose (`--verbose`).
- [x] Definir layout do store em `~/.spmx/store` (sobrescrevível via `SPMX_STORE_DIR`):
  - `~/.spmx/store/checkouts/<identity>-<revision>/`
  - `~/.spmx/store/artifacts/<identity>/<targetName>-<checksum>/`
  - `~/.spmx/store/prebuilts/<swift-version-hash>/<package-identity>-<version-or-checksum>/` (indexado com hash da versão do Swift/Xcode obtida via `swift --version` / `xcodebuild -version` para evitar incompatibilidade de ABI/módulos ao atualizar o Xcode)
  - `~/.spmx/store/index.json` (metadados de projetos/worktrees vinculados, fingerprint do toolchain e último acesso para `prune`).
- [x] Proteger escritas no store por pacote usando lock de arquivo POSIX (`flock`) com timeout configurável, garantindo segurança quando múltiplos worktrees executam `harvest`/`hydrate` ao mesmo tempo.
- [x] Testes unitários validando `clonefile()`, fallback, atomicidade, particionamento por versão do Swift/Xcode em `prebuilts/` e escrita concorrente com múltiplas tasks em paralelo.
- [x] `swift build` e `swift test` passam.

---

### US-004: Hidratação (`hydrate`) e Colheita (`harvest`) do `SourcePackages` e `workspace-state.json`

**Description:** As a developer, I want `spmx` to populate a worktree's `SourcePackages` (or `.build`) from the global store before a build and harvest any newly resolved packages and prebuilt macros back into the global store afterward, so that dependencies are never downloaded twice.

**Acceptance Criteria:**

- [x] **Comando `spmx hydrate` (alias `spmx install`):**
  - Lê `Package.resolved` (e opcionalmente cache de manifesto/artifacts/prebuilts associados às mesmas dependências e à versão ativa do Swift/Xcode).
  - Para cada pin encontrado no store global, clona via `clonefile()` para `<SourcePackages>/checkouts/<identity>` (ou `.build/checkouts/<identity>`), os artefatos correspondentes para `<SourcePackages>/artifacts/<identity>/<target>/` (ou `.build/artifacts/...`) e os binários de macros compatíveis com o toolchain atual para `<SourcePackages>/prebuilts/` (ou `.build/prebuilts/`).
  - Gera/atualiza `<SourcePackages>/workspace-state.json` reescrevendo caminhos locais/absolutos (especialmente `artifacts[].path` e eventuais paths de `prebuilts`) para apontar para o `SourcePackages` do worktree atual, evitando referências quebradas a outro worktree.
  - Nunca sobrescreve um checkout modificado manualmente pelo usuário sem flag `--force`.
- [x] **Comando `spmx harvest`:**
  - Inspeciona `<SourcePackages>/checkouts`, `<SourcePackages>/artifacts`, `<SourcePackages>/prebuilts` e `workspace-state.json` após execução do Xcode/SwiftPM.
  - Para qualquer pacote, artefato ou prebuilt válido (com checksum/revision completos e sem marcador `.partial`) ausente no `~/.spmx/store`, clona via `clonefile()` para o store global (com fingerprint do toolchain ativo para `prebuilts`) sob lock `flock`.
  - Registra o diretório do projeto/worktree no índice do store (`index.json`) para rastreamento de `prune`.
- [x] Suporte completo tanto para `DerivedData/.../SourcePackages` (Xcode/Flutter) quanto para `.build/` (SwiftPM CLI puro).
- [x] Testes de integração simulando Worktree A (popula cache + `harvest`) → Worktree B (`hydrate` sem rede) validando `checkouts`, `artifacts`, `prebuilts` e `workspace-state.json` com paths reescritos corretamente.
- [x] `swift build` e `swift test` passam.

---

### US-005: Integração Específica com Projetos Flutter (`FlutterGeneratedPluginSwiftPackage`)

**Description:** As a Flutter developer using Git worktrees with Swift Package Manager enabled, I want `spmx` to handle Flutter's ephemeral SPM package generation and `Package.resolved` reuse, so that running `flutter run` or `flutter build` in a new worktree doesn't stall on Xcode package resolution.

**Acceptance Criteria:**

- [x] Detectar presença de configuração SPM no Flutter (`ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage` ou `pubspec.yaml` + `.flutter-plugins-dependencies` / configuração SwiftPM habilitada).
- [x] Ao hidratar um novo worktree Flutter onde `ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift` ainda não existe, executar `flutter pub get` (via binário real do Flutter, sem loop de shim) antes de hidratar o `SourcePackages` do Xcode.
- [x] Armazenar no índice do store um hash das dependências nativas declaradas em `.flutter-plugins-dependencies` + `Package.swift` locais; quando um novo worktree possui o mesmo hash e ainda não tem `Package.resolved` gerado (caso esteja git-ignored ou desatualizado no worktree), restaurar o `Package.resolved` compatível antes do build.
- [x] Suportar tanto target `ios/` (`Runner.xcworkspace`) quanto target `macos/` (`Runner.xcworkspace`) em projetos Flutter multiplataforma.
- [x] Testes unitários com fixture de projeto Flutter simulando criação de worktree limpo sem `ephemeral/`.
- [x] `swift build` e `swift test` passam.

---

### US-006: Sistema de Shims Transparentes no `PATH` (Ativo por Padrão)

**Description:** As a developer, I want `spmx` to intercept `flutter`, `xcodebuild`, and `swift` commands automatically via PATH shims after installation, so that all existing and future Flutter/Swift projects benefit from global caching with zero workflow changes.

**Acceptance Criteria:**

- [x] Arquitetura de binário único multicall (estilo `puro`/BusyBox): ao iniciar, `spmx` inspeciona `URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent`:
  - `spmx`: executa a CLI do `spmx`.
  - `flutter`: executa fluxo de shim Flutter.
  - `xcodebuild`: executa fluxo de shim `xcodebuild`.
  - `swift`: executa fluxo de shim SwiftPM.
- [x] Symlinks criados por padrão em `~/.spmx/shims/{flutter,xcodebuild,swift}` apontando para `~/.spmx/bin/spmx`.
- [x] Resolução do binário real sem loop infinito: o shim filtra o diretório `~/.spmx/shims` do `PATH` ao procurar o próximo executável válido (`flutter`, `xcodebuild` ou `swift`), mantendo compatibilidade total com `puro`, `fvm`, `asdf`, `mise`, `xcodes` e `/usr/bin/xcodebuild`.
- [x] **Shim `flutter`:**
  - Só atua quando subcomando envolver iOS/macOS build/run (`run`, `build`, `test` em plataforma Apple, ou `pub get` quando `--no-spmx` não for passado); para subcomandos irrelevantes (`--version`, `doctor`, `analyze`, `build apk`), delega diretamente (`execv`) com overhead **< 5 ms**.
  - Seta variável de ambiente `SPMX_FLUTTER_SHIM_ACTIVE=1` ao invocar o `flutter` real, evitando hidratação duplicada redundante quando o `flutter` chamar `xcodebuild` internamente, mantendo apenas a colheita (`harvest`) ao final caso novos pacotes sejam baixados.
- [x] **Shim `xcodebuild`:**
  - Faz parsing leve dos flags `-workspace`, `-project`, `-clonedSourcePackagesDirPath`, `COMPILATION_CACHE_*` e ações (`-resolvePackageDependencies`, `build`, `archive`, `test`).
  - Se não houver `-clonedSourcePackagesDirPath` explícito passado pelo usuário/CI, hidrata automaticamente o `DerivedData/.../SourcePackages` alvo antes de executar o `/usr/bin/xcodebuild` real e executa `harvest` ao término se o comando resolver ou buildar pacotes.
  - Em ações de build (`build`, `archive`, `test`) no Xcode 16+ / Swift 6+, quando não desativado via `SPMX_NO_COMPILE_CACHE=1` e o usuário não tiver passado flags explícitas de cache, injeta flags nativas de Compilation Cache (LLVM CAS) compartilhado apontando para `~/.spmx/compilation-cache` (ex.: `COMPILATION_CACHE_ENABLE_CACHING=YES`, `COMPILATION_CACHE_ENABLE_PLUGIN_CACHING=YES`, `COMPILATION_CACHE_REMOTE_SERVICE_PATH` / caminho local conforme versão do Xcode suportada).
  - Respeita variável de bypass `SPMX_DISABLE=1` para desativar temporariamente qualquer shim.
- [x] **Shim `swift`:**
  - Intercepta `swift build`, `swift test`, `swift run` e `swift package resolve` quando houver `Package.swift` no diretório, hidratando `.build/` antes e fazendo `harvest` depois.
  - Quando suportado pelo toolchain Swift 6+ e `SPMX_NO_COMPILE_CACHE=1` não estiver setado, habilita cache de compilação global (`--enable-build-cache` / path em `~/.spmx/compilation-cache` quando aplicável).
- [x] Todos os códigos de saída (`exit code`), `stdin`, `stdout` e `stderr` (incluindo TTY/cores) do comando real são preservados integralmente.
- [x] Testes automatizados validando resolução de `PATH`, anti-loop, injeção/bypass de `COMPILATION_CACHE_*` (`SPMX_NO_COMPILE_CACHE=1`), preservação de exit codes e bypass total com `SPMX_DISABLE=1`.

---

### US-007: Git Hooks Opt-in para Worktrees (`spmx hooks enable | disable | status`)

**Description:** As a developer, I want the option to enable a global or per-repo Git `post-checkout` hook that automatically pre-warms `SourcePackages` the instant I run `git worktree add`, while keeping hooks disabled by default at install time.

**Acceptance Criteria:**

- [x] Git hooks iniciam **desativados por padrão** após a instalação (o `spmx` nunca altera `git config --global core.hooksPath` nem arquivos `.git/hooks/` sem consentimento explícito do usuário).
- [x] Comando `spmx hooks enable [--global | --repo]`:
  - Em modo `--repo` (padrão dentro de um repo Git): adiciona bloco delimitado por `# >>> spmx hook >>>` / `# <<< spmx hook <<<` ao `.git/hooks/post-checkout` preservando integralmente qualquer hook preexistente (ex: Lefthook, Husky, hooks manuais).
  - Em modo `--global`: configura diretório de hooks globais (ou encadeia caso `core.hooksPath` já esteja definido pelo usuário, avisando e mantendo compatibilidade).
  - O script do hook verifica se trata-se de criação de worktree / checkout de branch em projeto Flutter ou Swift (`if [ "$3" = "1" ]`) e dispara `spmx hydrate --quiet` (com opção `--async` se desejado).
- [x] Comando `spmx hooks disable [--global | --repo]` remove apenas o bloco delimitado pelo `spmx`, deixando outros hooks intactos.
- [x] Comando `spmx hooks status` exibe se hooks globais/locais estão ativos ou inativos.
- [x] Ao finalizar a instalação (`install.sh` e `spmx setup`), exibir banner informativo explicando:
  - Que os shims já estão ativos por padrão;
  - A capacidade e vantagem dos Git hooks ao criar worktrees (`git worktree add` já nasce com `SourcePackages` hidratado);
  - O comando exato para ativar caso o dev queira (`spmx hooks enable --global`).
- [x] Testes unitários validando inserção, encadeamento com hook existente e remoção limpa do bloco `# >>> spmx hook >>>`.

---

### US-008: Comandos de Gerenciamento, Inspeção e Diagnóstico (`store`, `status`, `doctor`)

**Description:** As a developer, I want `pnpm`-like store management commands (`spmx store path`, `spmx store status`, `spmx store prune`, `spmx doctor`) to inspect cached packages and compilation cache, see saved disk space, clean unused packages, and troubleshoot my setup.

**Acceptance Criteria:**

- [x] `spmx store path`: imprime o caminho absoluto do store global (`~/.spmx/store`).
- [x] `spmx store status`: lista total de `checkouts`, `artifacts` e `prebuilts` armazenados (agrupados por toolchain quando aplicável), tamanho lógico total no store, tamanho de `~/.spmx/compilation-cache`, número de worktrees/projetos registrados e estimativa de espaço economizado via Copy-on-Write.
- [x] `spmx store prune [--dry-run] [--older-than <dias>]`: verifica worktrees/projetos registrados em `index.json` (removendo entradas cujos diretórios não existem mais no disco), apaga pacotes (`checkouts`, `artifacts`, `prebuilts`) não referenciados por nenhum projeto/worktree ativo e aplica limpeza por idade/tamanho no `~/.spmx/compilation-cache`.
- [x] `spmx status` (no diretório de um projeto): mostra tipo de projeto detectado, versão do Xcode/Swift ativa, caminho calculado do `DerivedData`, quantos pacotes/prebuilts do `Package.resolved` já estão em cache no store vs. pendentes e estado do Compilation Cache.
- [x] `spmx doctor`: verifica sistema de arquivos APFS, presença do `xcodebuild`/Xcode, versão do Swift/suporte a LLVM CAS Compilation Cache, ordem do `PATH` (`~/.spmx/shims` antes de `flutter`, `xcodebuild`, `swift`), integridade do `~/.spmx/store` e `~/.spmx/compilation-cache`, compatibilidade com `puro`/`fvm` e estado dos Git hooks.
- [x] Testes unitários cobrindo lógica de `prune` (com `--dry-run`, incluindo `prebuilts` e `compilation-cache`) e checagens do `doctor`.

---

### US-009: Instalador One-Liner (`curl | sh`) e Distribuição via Homebrew

**Description:** As a developer, I want to install `spmx` globally on macOS with a single `curl` command or `brew install`, so that every existing and future Flutter/Swift project works seamlessly out of the box.

**Acceptance Criteria:**

- [x] Script `scripts/install.sh` (compatível com `curl -fsSL ... | sh`):
  - Detecta arquitetura (`arm64` / `x86_64`) e OS (`Darwin`), baixa o release tarball + verifica checksum SHA-256.
  - Instala o binário em `~/.spmx/bin/spmx` e cria os symlinks de shim em `~/.spmx/shims/` (`flutter`, `xcodebuild`, `swift`).
  - Executa `spmx setup`, que adiciona `export PATH="$HOME/.spmx/shims:$HOME/.spmx/bin:$PATH"` ao perfil do shell detectado (`~/.zshrc`, `~/.bashrc`, `~/.config/fish/config.fish`) de forma idempotente (com suporte a `--no-modify-path`).
  - Exibe resumo pós-instalação mostrando os shims ativados e a recomendação opcional de `spmx hooks enable --global`.
- [x] Comando `spmx uninstall` remove shims, entradas idempotentes no shell RC e opcionalmente o `~/.spmx/store` (mediante flag `--purge` ou confirmação).
- [x] Workflow de CI no GitHub Actions (`.github/workflows/release.yml`):
  - Roda testes (`swift test`), compila Universal Binary (`swift build -c release --arch arm64 --arch x86_64`), empacota `spmx-macos-universal.tar.gz` + `.sha256` e publica GitHub Release.
  - Documentação e template da Fórmula Homebrew (`Formula/spmx.rb`) pronta para tap (`brew install <org>/tap/spmx`), com bloco `caveats` instruindo a adicionar `~/.spmx/shims` ao `PATH` (ou rodar `spmx setup`) e mencionando o opt-in de hooks.

---

## 4. Functional Requirements

- **FR-1:** O sistema deve rodar nativamente em macOS (Apple Silicon `arm64` e Intel `x86_64`) como um único binário compilado em Swift sem dependências externas em tempo de execução.
- **FR-2:** O sistema deve calcular o diretório `DerivedData` do Xcode usando exatamente o algoritmo MD5 + base-26 de 28 caracteres a partir do path canônico do `.xcworkspace` ou `.xcodeproj`.
- **FR-3:** O sistema deve ler e suportar `Package.resolved` nos formatos `v1`, `v2` e `v3`, além de `workspace-state.json` do SwiftPM.
- **FR-4:** O sistema deve armazenar pacotes imutáveis em `~/.spmx/store` indexados por `<identity>-<revision>` (para `checkouts`), `<identity>/<targetName>-<checksum>` (para `artifacts`) e `<swift-version-hash>/<identity>-<version-or-checksum>` (para `prebuilts` de Swift Macros), registrando a versão do Swift/Xcode nos metadados do store.
- **FR-5:** Ao hidratar um projeto/worktree, o sistema deve utilizar a syscall `clonefile()` em volumes APFS, garantindo isolamento de escrita entre worktrees sem duplicação física no disco, e fazer fallback seguro em volumes não-APFS ou cross-volume (`EXDEV`).
- **FR-6:** Ao hidratar `workspace-state.json`, o sistema deve atualizar todos os caminhos absolutos internos (como paths de `.xcframework` em `artifacts/` e `prebuilts/`) para corresponder ao diretório de destino do worktree atual.
- **FR-7:** Após a instalação (`spmx setup` / `install.sh`), os shims `flutter`, `xcodebuild` e `swift` em `~/.spmx/shims` devem ficar ativos por padrão no `PATH`.
- **FR-8:** Os shims devem localizar o executável real no `PATH` ignorando `~/.spmx/shims`, garantindo interoperabilidade com `puro`, `fvm`, `asdf`, `mise` e Xcode CLI, ativando o cache de compilação nativo LLVM CAS (`COMPILATION_CACHE_ENABLE_CACHING=YES`, `COMPILATION_CACHE_ENABLE_PLUGIN_CACHING=YES`) quando suportado pelo toolchain, e suportando desativação via `SPMX_DISABLE=1` (shim completo) ou `SPMX_NO_COMPILE_CACHE=1` (apenas compilation cache).
- **FR-9:** Em projetos Flutter com SwiftPM, quando o diretório efêmero `FlutterGeneratedPluginSwiftPackage` não existir em um novo worktree, o sistema deve acionar `flutter pub get` (via binário real) antes da hidratação do `SourcePackages`.
- **FR-10:** O suporte a Git Hooks (`post-checkout`) deve permanecer **desativado por padrão** na instalação, podendo ser ativado/desativado a qualquer momento pelo usuário via `spmx hooks enable` / `spmx hooks disable`, sempre preservando hooks preexistentes.
- **FR-11:** Todas as operações de escrita no `~/.spmx/store` devem usar `flock` e staging atômico para suportar execução paralela de múltiplos worktrees ou agentes de IA.
- **FR-12:** O sistema não deve coletar telemetria nem enviar dados de rede por conta própria (exceto quando o usuário executar explicitamente atualização/instalação ou delegar ao `flutter`/`xcodebuild`/`swift` reais).

---

## 5. Non-Goals (Out of Scope na v1) & Roadmap v2

- **Substituição do solver de dependências do SwiftPM:** Na v1, o `spmx` delega a resolução inicial do grafo de versões ao próprio `xcodebuild` / `swift package resolve` (similar à estratégia do `swifterpm`), otimizando o armazenamento, reutilização e restauração física em disco.
- **Proxy Binary Cache (`.xcframework` estilo `xccache`) no `FlutterGeneratedPluginSwiftPackage` (Roadmap v2):** Na v1, o `spmx` **não** converte pacotes de código-fonte em `.xcframework` estáticos nem reescreve manifests de proxy packages. Essa abordagem fica reservada para avaliação na **v2 / experimental** pelos motivos detalhados na seção 6.7 (sobrescrita de `ephemeral/` pelo `flutter_tools`, acoplamento de slices de `Flutter.xcframework`, quebra de `Bundle.module` / `PrivacyInfo.xcprivacy` e símbolos duplicados). Na v1, a reutilização de compilação de pacotes source é atendida de forma segura pelo **LLVM CAS Compilation Cache** nativo do Xcode/Swift.
- **Cache remoto distribuído de build (estilo Bazel / Tuist Cloud):** O foco da v1 é store local e compartilhado na máquina (`~/.spmx/store` e `~/.spmx/compilation-cache`), sem servidor remoto de cache compilado.
- **Suporte a Windows e Linux na v1:** Como `clonefile()` (APFS) e `DerivedData`/Xcode são específicos do macOS, a v1 foca exclusivamente em macOS. Suporte Linux (hardlinks / `FICLONE` para SwiftPM puro) fica para o roadmap pós-v1.
- **Interface Gráfica (GUI / Menu Bar App):** O `spmx` na v1 é exclusivamente uma ferramenta de linha de comando (CLI).
- **Substituição do CocoaPods:** Projetos Flutter ou iOS que ainda utilizam exclusivamente CocoaPods (`Podfile` sem SwiftPM) não terão cache gerenciado para `Pods/` pelo `spmx`.

---

## 6. Technical Considerations

### 6.1. Por que Swift como Linguagem do CLI
- **Compatibilidade nativa com Darwin/APFS:** Acesso direto à função `clonefile` via `import Darwin` (`<sys/clonefile.h>`), `flock`, e `CryptoKit` (`Insecure.MD5`) sem camadas de FFI ou runtimes embutidos.
- **Startup ultrarrápido (~2 ms):** Crítico para shims no `PATH` que interceptam comandos frequentes como `flutter` e `swift`.
- **Binário Universal compacto (~3 MB):** Usa as bibliotecas dinâmicas do sistema operacional (`/usr/lib/swift`), dispensando instalação de toolchain extra pelo usuário final via `brew` ou `curl`.
- **Ecossistema alinhado:** Contribuidores Swift/iOS conseguem ler e manter o parser de `Package.resolved`, `workspace-state.json` e regras de Xcode nativamente.

### 6.2. Por que `clonefile()` (APFS CoW) em vez de Symlinks
- Ferramentas e build phases do Xcode/Flutter frequentemente falham com symlinks dentro de `SourcePackages/artifacts/` (validação de assinatura de `.xcframework`, sandboxing do `xcodebuild` e caminhos relativos no `workspace-state.json`).
- A syscall `clonefile(src, dst, 0)` no macOS cria entradas reais no sistema de arquivos que compartilham exatamente os mesmos blocos físicos no SSD via Copy-on-Write. Se algum processo modificar um arquivo dentro de um worktree, apenas o bloco alterado é alocado no disco — mantendo o store global imutável e intacto.

### 6.3. Cálculo do Hash do `DerivedData` do Xcode
O Xcode nomeia cada pasta de build como `<ProductOrWorkspaceName>-<28_lowercase_letters>`. Os 28 caracteres são derivados deterministicamente do digest MD5 (16 bytes) do path absoluto canônico do `.xcworkspace` ou `.xcodeproj` (sem barra final), divididos em dois inteiros `UInt64` big-endian convertidos para base-26 (`a`–`z`, 14 caracteres cada). Esse algoritmo deve ser validado contra o output real de `xcodebuild -showBuildSettings` nos testes de integração da US-001.

### 6.4. Coordenação de Shims (`flutter` + `xcodebuild` + `puro`/`fvm`)
Quando o desenvolvedor executa `flutter run` ou `flutter build ios`:
1. O `PATH` resolve primeiro `~/.spmx/shims/flutter`.
2. O shim `flutter` garante que `FlutterGeneratedPluginSwiftPackage` exista (rodando `flutter pub get` se necessário via o binário real de Flutter — seja do `puro`, `fvm` ou SDK direto), hidrata o `SourcePackages` do `Runner.xcworkspace`, marca `SPMX_FLUTTER_SHIM_ACTIVE=1` e delega ao `flutter` real.
3. Internamente, o `flutter` invoca `xcodebuild`. O shim `xcodebuild` vê `SPMX_FLUTTER_SHIM_ACTIVE=1`, evita repetir hidratação redundante de rede/disco se o `SourcePackages` já foi hidratado naquele comando, ativa o LLVM CAS Compilation Cache (se não bloqueado via `SPMX_NO_COMPILE_CACHE=1`) e garante o `harvest` após a conclusão do `xcodebuild` caso novos pacotes tenham sido baixados.
4. Se o desenvolvedor executar `xcodebuild` diretamente (ou abrir o Xcode via CLI / projeto Swift puro), o shim `xcodebuild` executa o ciclo completo de `hydrate` + execução real (com LLVM CAS) + `harvest`.

### 6.5. Nota sobre Abertura Direta pelo Xcode GUI
Quando o usuário abre `Runner.xcworkspace` diretamente pela interface gráfica do Xcode (sem passar pelo terminal/shims), o Xcode GUI não passa pelo `PATH` do shell. Para esses casos, o usuário pode habilitar os **Git Hooks (`spmx hooks enable --global`)**, garantindo que o `SourcePackages` já esteja pré-hidratado no instante em que o worktree foi criado, antes mesmo de o Xcode GUI ser aberto.

### 6.6. Insights Incorporados da Análise do `xccache` (`prebuilts/` + LLVM CAS + Toolchain Hash)
Da análise de arquiteturas de binary cache como o `xccache`, o `spmx` incorpora três melhorias seguras e Zero-Config na v1:
- **`SourcePackages/prebuilts/` (Swift Macros):** SwiftPM armazena binários pré-compilados de macros (como `swift-syntax`) em `prebuilts/`. Cloná-los via `clonefile()` elimina recompilações de 30–60s de macros em novos worktrees.
- **Fingerprint de Versão Xcode/Swift:** Itens dependentes de toolchain (`prebuilts/` e metadados de compilação) são particionados pelo hash de `swift --version` / `xcodebuild -version`, prevenindo incompatibilidades de ABI/módulos após updates do Xcode.
- **Cache de Compilação Nativo (LLVM CAS):** Em vez de reempacotar pacotes source em `.xcframework`, o shim `xcodebuild`/`swift` habilita `COMPILATION_CACHE_ENABLE_CACHING=YES` e `COMPILATION_CACHE_ENABLE_PLUGIN_CACHING=YES` apontando para `~/.spmx/compilation-cache`, reaproveitando unidades compiladas (`.o`/`.swiftmodule`) entre worktrees no nível do compilador, sem tocar no `project.pbxproj` nem em manifests `Package.swift`.

### 6.7. Por que Proxy Binary Cache (`.xcframework`) Fica Fora da v1
Converter targets SPM em `.xcframework` estáticos dentro de `FlutterGeneratedPluginSwiftPackage` (estilo `xccache`) na v1 traria cinco desvantagens críticas:
1. **Conflito de ciclo de vida:** `flutter_tools` sobrescreve `ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift` durante `pub get`/`run`/`build`.
2. **Acoplamento com Engine Flutter:** Plugins fazem `import Flutter`/`FlutterMacOS`, exigindo extração manual de `Flutter.xcframework` por arquitetura/configuração (`Debug`/`Release`, simulator/device).
3. **Quebra de `Bundle.module` e `PrivacyInfo.xcprivacy`:** Exige patching frágil de `resource_bundle_accessor.swift.o` antes do `libtool`.
4. **Símbolos duplicados & Module Stability:** Plugins com subdependências compartilhadas ou código C/ObjC frequentemente falham no linker com `duplicate symbol` ou não suportam `BUILD_LIBRARY_FOR_DISTRIBUTION=YES`.
5. **Baixo retorno incremental na v1:** SDKs pesados (Firebase, Google Ads, WebRTC) já são distribuídos como `.xcframework` em `SourcePackages/artifacts/`, e pacotes source já são acelerados pelo LLVM CAS nativo sem hacks frágeis.

---

## 7. Success Metrics

- **Tempo de setup de novo worktree (cache quente):** Redução de **≥ 90%** no tempo da etapa `Resolving Package Graph` / `xcodebuild -resolvePackageDependencies` em projetos Flutter + Firebase/SPM (ex.: de 60–180s para < 2s).
- **Economia de disco por worktree:** Consumo incremental em disco de `SourcePackages` por worktree adicional **< 5 MB** (apenas metadados/estados reescritos) mesmo para dependências que somam > 1 GB.
- **Overhead de shim no-op:** Latência adicional introduzida pelo shim ao rodar comandos não-Apple/não-SPM (ex.: `flutter --version`, `swift --version`) **< 5 ms**.
- **Taxa de sucesso Zero-Config:** 100% dos comandos `flutter run`, `flutter build ios`, `xcodebuild` e `swift build` em worktrees novos reutilizando o store sem requerer flags manuais após instalação padrão.

---

## 8. Open Questions

1. **Formato do nome de comando e tap Homebrew:** O projeto será hospedado em qual organização/usuário do GitHub (ex.: `github.com/<org>/spmx`) para definir o endereço oficial do `install.sh` e do Homebrew Tap?
2. **Suporte a Xcode GUI via LaunchAgent ou apenas Git Hooks/CLI:** Na v1, o Git Hook `post-checkout` opt-in + shims já cobrem a abertura via GUI após criar o worktree; devemos avaliar na v2 um watcher leve ou plugin/comando `spmx open` (que hidrata e abre o Xcode)?
3. **Uso com `puro flutter` explícito:** Quando um dev usa `puro` no modo `puro flutter run` (em vez de `flutter run`), o `puro` executa o binário interno diretamente sem passar pelo shim `flutter` do `PATH`, porém o `xcodebuild` chamado pelo Flutter ainda passará pelo shim `~/.spmx/shims/xcodebuild`! Devemos documentar isso no `spmx doctor` ou também considerar um shim opcional/aviso para `puro`?
4. **Política padrão do `spmx store prune`:** Qual deve ser o TTL padrão para sugerir limpeza de pacotes órfãos e entradas do `~/.spmx/compilation-cache` (ex.: 30 dias sem nenhum worktree/projeto ativo referenciando)?
