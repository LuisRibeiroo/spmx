# PRD: Store Global Compartilhado na Máquina Toda (Estilo Puro / pnpm) & Pivot de Posicionamento GTM

## 1. Introduction / Overview

Hoje, o `spmx` já armazena pacotes de forma endereçável por conteúdo em `~/.spmx/store`, mas tanto alguns detalhes internos da engine quanto **100% da comunicação do produto (`README.md`, `spmx.io`, diagramas e documentação)** foram construídos em torno do caso de uso de múltiplos `git worktree`s de um mesmo repositório.

Este PRD especifica a evolução técnica e estratégica do `spmx` para operar e se posicionar como **o Store Global de Swift Package Manager para a máquina toda** (seguindo a mesma filosofia do **Puro** no Flutter e do **pnpm** no Node.js):

- **Exemplo canônico de deduplicação por `(pacote, versão)`:**
  - **Projeto A** usa: `firebase 1.0.0`, `stripe 3.4.5`, `xyz 4.0.0`
  - **Projeto B** usa: `xyz 4.0.0`, `abc 1.0.0`
  - **Projeto C** usa: `firebase 1.0.1`, `stripe 3.4.5`
  - **Store Global (`~/.spmx/store`) mantém uma única instalação física de cada corte `(pacote, versão)`:**
    - `firebase @ 1.0.0` (puxado pelo Projeto A)
    - `firebase @ 1.0.1` (puxado pelo Projeto C)
    - `stripe @ 3.4.5` (compartilhado entre Projeto A e Projeto C via APFS `clonefile()`)
    - `abc @ 1.0.0` (puxado pelo Projeto B)
    - `xyz @ 4.0.0` (compartilhado entre Projeto A e Projeto B via APFS `clonefile()`)

Além de fechar os 5 gaps técnicos que ocorrem quando projetos distintos na máquina compartilham parcialmente o mesmo store, este PRD incorpora os controles de vínculo (`spmx link [path]` / `spmx unlink [path]`), a estimativa de espaço economizado **por projeto e no global**, e a reescrita completa do pitch, `README.md`, landing page (`spmx.io`) e documentação guiada pelas skills do **[gtm-cofounder](https://github.com/AIDevGTM/gtm-cofounder)** ([`docs/gtm-cofounder/founder-brief.md`](../docs/gtm-cofounder/founder-brief.md) e [`docs/gtm-cofounder/gtm-roadmap.md`](../docs/gtm-cofounder/gtm-roadmap.md)).

---

## 2. Análise de Riscos Técnicos e Mitigações Obrigatórias

| # | Risco Técnico entre Projetos Diferentes | Impacto sem Mitigação | Mitigação Obrigatória neste PRD |
| :--- | :--- | :--- | :--- |
| **R1** | **Hidratação Parcial (`Cache Hit` parcial)** — Ex.: Projeto B tem `xyz 4.0.0` no store, mas `abc 1.0.0` ainda não existe no store. | Se o `workspace-state.json` sintetizado para o Projeto B tiver schema fixo ou incompleto, o SwiftPM/Xcode pode descartar o estado e baixar `xyz 4.0.0` novamente ao resolver `abc 1.0.0`. | Preservar a versão nativa do schema de `workspace-state.json` e todos os fragmentos JSON originais por `(identity, revision)` em `PackageTemplateRecord`, garantindo que o SwiftPM resolva apenas o delta (`abc 1.0.0`) mantendo `xyz 4.0.0` intacto. |
| **R2** | **Ausência de `SourcePackages/repositories/` (Bare Git Repos)** — Projetos diferentes frequentemente pedem versões adjacentes (`firebase 1.0.0` vs `1.0.1`) ou resolvem grafos parciais. | Sem os bare repos em `SourcePackages/repositories/`, o SwiftPM pode re-clonar centenas de MB da rede durante resoluções parciais ou ao subir de `1.0.0` para `1.0.1`. | Adicionar cache de bare repositories em `~/.spmx/store/repositories/<identity>` clonados via APFS CoW para `SourcePackages/repositories/`, permitindo validação offline pelo SwiftPM e `git fetch` incremental entre versões. |
| **R3** | **Colheita (`harvest`) de Checkout Sujo ("Dirty Working Tree")** — Dev edita arquivo dentro de `SourcePackages/checkouts/stripe` no Projeto A para debugar. | Um `harvest` com `--overwrite` ou em nova revisão poderia copiar código modificado localmente para `~/.spmx/store`, afetando o Projeto C. | Validar obrigatoriamente no `harvest` que o checkout possui `git status --porcelain` limpo e `git rev-parse HEAD == revision` antes de salvar no store global. |
| **R4** | **Projetos Flutter Diferentes (`FlutterGeneratedPluginSwiftPackage`)** — App Flutter A e App Flutter B têm `.flutter-plugins-dependencies` diferentes. | O hash global do `.flutter-plugins-dependencies` não bate entre apps diferentes, perdendo oportunidades de pré-hidratação antes do primeiro `Package.resolved`. | Além de hidratar normalmente quando `Package.resolved` já existe, inspecionar os plugins de `.flutter-plugins-dependencies` para pré-aquecer `repositories/`, `checkouts/`, `artifacts/` e `prebuilts/` conhecidos no `SourcePackages` do projeto Flutter. |
| **R5** | **Falta de Opção de Opt-Out Local (`unlink`) e Visibilidade SemVer** — Nem todo projeto da máquina pode ou deve usar o store global, e hashes SHA-1 não comunicam versões (`1.0.0` vs `1.0.1`). | O dev não sabe quais versões semânticas estão no store, quanto espaço cada projeto economiza, nem consegue isolar um projeto específico para usar apenas o cache local do Xcode. | Implementar `spmx unlink [path]` / `spmx link [path]`, indexar versões semânticas (`1.0.0`, `3.4.5`) no `StoreIndex` e exibir economia de disco aproximada por projeto e no global. |

---

## 3. Goals

- **G-1 (Deduplicação Machine-Wide por Versão):** Garantir que qualquer pacote na mesma `(identity, version/revision)` seja armazenado uma única vez em `~/.spmx/store` e compartilhado via APFS `clonefile()` entre todos os projetos vinculados da máquina (Swift, Xcode, Flutter, React Native, Expo, Capacitor, KMP), suportando múltiplas versões do mesmo pacote lado a lado (`firebase 1.0.0` e `firebase 1.0.1`).
- **G-2 (Hidratação Parcial + Cache de `repositories/`):** Permitir que um projeto com interseção parcial de dependências (ex.: Projeto B com 1 pacote já no store e 1 pacote inédito) aproveite 100% dos pacotes já presentes no store sem re-download, e aproveite o histórico Git bare (`repositories/`) ao baixar novas versões (`1.0.0` → `1.0.1`).
- **G-3 (Controle de Vínculo e Varredura com Confirmação — `link` / `unlink`):** Manter o vínculo automático global por padrão via shims, mas permitir excluir qualquer projeto (`spmx unlink [path]`) para que ele use exclusivamente o cache local padrão, e permitir varrer um `<path>` específico ou a máquina toda (`spmx link [path]` / `spmx migrate [path]`) com confirmação interativa antes de executar.
- **G-4 (Transparência de Versões e Economia de Espaço):** Exibir as versões semânticas instaladas, quais projetos usam cada versão e o valor aproximado de espaço em disco economizado **por projeto** (`spmx status`) e **no global da máquina** (`spmx store status` / `spmx store list`).
- **G-5 (Pivot de GTM no README, Site e Docs via `gtm-cofounder`):** Reescrever o posicionamento, `README.md`, `spmx.io` (landing page, `StoreDiagram`, `CliSample`, FAQ) e documentação aplicando os frameworks de `who-is-this-for`, `positioning-and-story`, `value-prop-that-converts`, `the-homepage`, `founder-led-content`, `time-to-first-value` e `review-the-work`.

---

## 4. User Stories

### US-001: Indexação por Versão Semântica e Mapeamento Multi-Projeto no `GlobalStore`

**Description:** Como desenvolvedor com vários projetos na máquina, eu quero que o `~/.spmx/store` registre a versão semântica (`1.0.0`, `1.0.1`, `3.4.5`) de cada revisão e quais projetos dependem de cada corte `(pacote, versão)`, para que o store gerencie múltiplas versões lado a lado com visibilidade estilo Puro/pnpm.

**Acceptance Criteria:**

- [ ] Atualizar `PackageTemplateRecord` e `StoreIndex` (`Sources/SPMXCore/Store/GlobalStore.swift` e `Sources/SPMXCore/Sync/PackageSyncEngine.swift`) para armazenar `version: String?`, `branch: String?` e `location: String?` associados a cada `(identity, revision)`.
- [ ] Atualizar `StoreIndex.RegisteredProject` para persistir a lista de pins resolvidos (`PinnedDependency`: `identity`, `version`, `branch`, `revision`) além de `packageIdentities`, mantendo compatibilidade retroativa na leitura de `index.json` existentes (schema migration transparente).
- [ ] Garantir que duas versões diferentes do mesmo pacote (ex.: `firebase 1.0.0` com revision `revA` e `firebase 1.0.1` com revision `revB`) coexistam no store sem colisão e que cortes idênticos (`stripe 3.4.5` no Projeto A e Projeto C) apontem para a mesma entrada física no store.
- [ ] Testes unitários cobrindo o cenário exato: Projeto A (`firebase 1.0.0`, `stripe 3.4.5`, `xyz 4.0.0`), Projeto B (`xyz 4.0.0`, `abc 1.0.0`) e Projeto C (`firebase 1.0.1`, `stripe 3.4.5`).
- [ ] `swift build` e `swift test` passam sem warnings.

---

### US-002: Cache de `SourcePackages/repositories/` (Bare Git Repos) e Hidratação Parcial entre Projetos

**Description:** Como desenvolvedor abrindo ou compilando um Projeto B que compartilha apenas parte das dependências com o Projeto A (ou um Projeto C que usa uma versão `1.0.1` de um pacote que já tenho na `1.0.0`), eu quero que o `spmx` hidrate tanto os `checkouts` quanto os `repositories` bare do SwiftPM e preserve o `workspace-state.json` nativo, para que o Xcode/SwiftPM nunca baixe de novo o que já está no store.

**Acceptance Criteria:**

- [ ] Adicionar diretório `~/.spmx/store/repositories/` ao layout do `GlobalStore` para armazenar e atualizar os bare repositories de `SourcePackages/repositories/<identity>-<hash>/`.
- [ ] Durante o `harvest`, colher os diretórios bare de `SourcePackages/repositories/` (ignorando diretórios `.partial` ou corrompidos) e mapear o nome da pasta `<identity>-<shortHash>` no template do pacote (`PackageTemplateRecord`). Se o repositório bare já existir no store e a nova colheita tiver commits adicionais (ex.: `1.0.1` após `1.0.0`), atualizar a entrada no store de forma segura sob `FileLock`.
- [ ] Durante o `hydrate`, clonar via APFS `clonefile()` os bare repositories correspondentes para `SourcePackages/repositories/<identity>-<shortHash>` junto dos `checkouts/<subpath>`.
- [ ] Atualizar `materializeWorkspaceState` em `PackageSyncEngine.swift` para preservar o número de `version` do `workspace-state.json` colhido da toolchain ativa (usando `7` apenas como fallback inicial) e manter todos os campos nativos de cada dependência em hidratações parciais (quando apenas um subconjunto dos pins de `Package.resolved` está no store).
- [ ] Testes unitários e de integração validando hidratação parcial (Projeto B com `xyz 4.0.0` em cache e `abc 1.0.0` ausente) e coexistência de `repositories/` + `checkouts/`.
- [ ] `swift build` e `swift test` passam sem erros.

---

### US-003: Guarda contra Checkout Sujo no `harvest` e Pré-Hidratação Cross-Project no Flutter

**Description:** Como desenvolvedor que às vezes edita código dentro de `SourcePackages/checkouts/` para debug ou trabalha em vários apps Flutter diferentes, eu quero que o `spmx harvest` nunca contamine o store global com checkouts modificados e que projetos Flutter distintos compartilhem pacotes nativos mesmo antes de terem o mesmo `dependencyHash`.

**Acceptance Criteria:**

- [ ] No método `harvest` de `PackageSyncEngine.swift`, executar verificação de integridade Git (`checkGitWorkingTree` com `git status --porcelain` limpo e verificação de que `git rev-parse HEAD` bate com a `revision` esperada) antes de salvar qualquer checkout em `~/.spmx/store/checkouts/`. Checkouts sujos ou com `HEAD` divergente devem ser ignorados e registrados em `skippedItems` com motivo explícito (`"locally modified working tree"` / `"HEAD revision mismatch"`).
- [ ] No `FlutterSPMIntegrator.swift`, quando um projeto Flutter B tiver um `dependencyHash` inédito (diferente do Projeto Flutter A), mas já possuir `Package.resolved` ou plugins em `.flutter-plugins-dependencies` que referenciam pacotes já presentes no store, garantir que o `hydrate` clone todos os `repositories`, `checkouts`, `artifacts` e `prebuilts` compatíveis antes da execução do `flutter`/`xcodebuild`.
- [ ] Testes cobrindo rejeição de checkout sujo no `harvest` e compartilhamento de pacotes entre dois projetos Flutter com listas de plugins diferentes (`App A` vs `App B`).
- [ ] `swift build` e `swift test` passam sem erros.

---

### US-004: Comandos `spmx link [path]` e `spmx unlink [path]` (Opt-Out por Projeto e Varredura com Confirmação)

**Description:** Como desenvolvedor, eu quero que todos os projetos da máquina usem o store global por padrão, mas quero poder desvincular um projeto específico (`spmx unlink [path]`) para que ele use apenas o cache local do Xcode/SwiftPM, e quero poder rodar uma varredura (`spmx link [path]` ou `spmx migrate [path]`) em um diretório específico ou na máquina toda com confirmação antes de executar.

**Acceptance Criteria:**

- [ ] Adicionar lista `excludedProjects: [String: ExcludedProjectRecord]` ao `StoreIndex` (`~/.spmx/store/index.json`) e suporte a arquivo marcador opcional `.spmxignore` na raiz do projeto.
- [ ] Implementar o comando `spmx unlink [path]` (default: diretório atual):
  - Registra o caminho canônico do projeto em `excludedProjects` no `index.json` (e remove de `projects` ativos vinculados);
  - Garante que o `SourcePackages` local do projeto continue íntegro e independente do store global;
  - Faz com que os shims (`swift`, `xcodebuild`, `flutter`), os Git hooks e as varreduras futuras ignorem aquele projeto e executem o binário nativo diretamente (*pass-through* puro para o cache local).
- [ ] Implementar o comando `spmx link [path]` e unificar o comportamento de varredura com `spmx migrate [path]`:
  - Se `<path>` apontar diretamente para um único projeto que estava em `excludedProjects`, remove-o da lista de exclusão, vincula-o novamente ao `~/.spmx/store` e executa `harvest` + `hydrate` após confirmação;
  - Se `<path>` apontar para uma pasta contendo projetos (ex.: `spmx link ~/projects/cliente-x` ou `spmx migrate ~/projects/cliente-x`) ou se `<path>` for omitido (**default: máquina toda**, cobrindo `~/Library/Developer/Xcode/DerivedData` e os diretórios de projetos do usuário em `~`), realiza a descoberta de todos os projetos SwiftPM/Xcode/Flutter no escopo (ignorando projetos desvinculados via `unlink`);
  - Antes de modificar qualquer arquivo no disco, exibe o plano completo (projetos encontrados, pacotes/versões a colher e deduplicar, e estimativa de espaço economizado por projeto e no total) e **solicita confirmação interativa (`Proceed with linking and deduplicating N projects? [y/N]`)**;
  - Suporta `--yes` / `-y` para execução não-interativa (CI/scripts) e `--dry-run` para apenas exibir o relatório sem perguntar nem alterar o disco.
- [ ] Testes cobrindo `spmx unlink`, *pass-through* dos shims em projeto desvinculado, re-vinculação com `spmx link <project>`, varredura com `<path>` específico, varredura default e prompt de confirmação.
- [ ] `swift build` e `swift test` passam sem erros.

---

### US-005: Relatório de Versões e Economia de Espaço por Projeto e Global (`status`, `store list`, `store status`)

**Description:** Como desenvolvedor, eu quero rodar `spmx status`, `spmx store list` e `spmx store status` para ver claramente todas as versões instaladas no store global, quais projetos puxam de cada versão e quanto espaço em disco está sendo economizado aproximadamente em cada projeto e na máquina toda.

**Acceptance Criteria:**

- [ ] Atualizar `spmx store list` (`StoreManager.swift` / `StoreCommand.swift`) para agrupar e exibir pacotes por identidade e **versão semântica** (ex.: `firebase-ios-sdk @ 1.0.0 (rev 7a8b9c1d)`, `firebase-ios-sdk @ 1.0.1 (rev 4d5e6f7a)`, `stripe-ios @ 3.4.5 (rev 9f0e1a2b)`), tamanho de cada corte e a lista/contagem de projetos vinculados que puxam daquela versão.
- [ ] Atualizar `spmx status` (`ProjectStatusInspector.swift` / `StatusCommand.swift`) para exibir:
  - Estado do vínculo do projeto (`Linked to global store` ou `Unlinked (using local project cache)`);
  - Lista de pacotes com sua versão semântica (`1.0.0`, `3.4.5`) e status no store (`hydrated / CoW clone`, `in store`, `missing`);
  - **Espaço aproximado economizado neste projeto** (`Estimated disk saved in this project: ~X.X GB / MB`), calculado pela soma dos tamanhos de `checkouts`, `repositories`, `artifacts` e `prebuilts` do projeto que são clones APFS CoW do `~/.spmx/store`.
- [ ] Atualizar `spmx store status` para exibir:
  - Resumo de espaço economizado **por projeto vinculado** (tabela/lista com nome/caminho abreviado do projeto, quantidade de pacotes compartilhados e espaço economizado naquele projeto);
  - **Total global aproximado de espaço economizado na máquina toda** (`Total estimated disk saved across machine: ~X.X GB`), somando a deduplicação entre projetos e `DerivedData`s frente ao custo de armazenamento único no `~/.spmx/store`.
- [ ] Manter suporte a `--json` em todos os comandos (`status --json`, `store list --json`, `store status --json`) incluindo os novos campos de versão semântica, projetos vinculados, `excludedProjects`, `projectSavedBytes` e `totalMachineSavedBytes`.
- [ ] Testes unitários validando o cálculo de espaço economizado por projeto e global e a formatação de saída CLI e JSON.
- [ ] `swift build` e `swift test` passam sem erros.

---

### US-006: Reescrita do `README.md` e Documentação Técnica com as Skills do `gtm-cofounder`

**Description:** Como visitante do repositório GitHub ou da documentação em `spmx.io/docs`, eu quero entender imediatamente que o `spmx` é um store global na máquina toda (estilo Puro / pnpm para SwiftPM) que elimina downloads e gigabytes duplicados entre todos os meus projetos, branches e worktrees.

**Acceptance Criteria:**

- [ ] Reescrever `README.md` seguindo a anatomia da skill **`founder-led-content`**, **`positioning-and-story`**, **`value-prop-that-converts`** e **`time-to-first-value`**:
  1. **One-line hook sem jargão vazio:** Definir o `spmx` como o store global na máquina para Swift Package Manager (como o Puro no Flutter ou o pnpm no Node.js), compartilhado via APFS copy-on-write entre todos os projetos, branches e worktrees no Mac.
  2. **O Problema e o Exemplo Multi-Projeto (`Projeto A`, `Projeto B`, `Projeto C`):** Mostrar visualmente como `firebase 1.0.0`, `firebase 1.0.1`, `stripe 3.4.5`, `abc 1.0.0` e `xyz 4.0.0` ficam salvos uma única vez no `~/.spmx/store` e são puxados instantaneamente por qualquer projeto na máquina.
  3. **Quickstart em < 2 minutos (`time-to-first-value`):** `curl -fsSL https://get.spmx.io | sh` → `spmx setup` → `spmx link` (varredura da máquina com confirmação mostrando quantos GB você acabou de recuperar).
  4. **Controle total (`link` / `unlink`):** Explicar que todos os projetos usam o store global por padrão, como excluir um projeto para usar o cache local (`spmx unlink`) e como inspecionar a economia por projeto e global (`spmx status`, `spmx store list`).
  5. **Prova e Benchmarks:** Dados reais medidos em `spmx.io/benchmarks`.
- [ ] Atualizar as páginas de documentação em `website/content/docs/` (`index.mdx`, `getting-started/installation.mdx`, `getting-started/quickstart.mdx`, `concepts/global-store.mdx`, `commands/store.mdx`, `commands/status.mdx`, e adicionar/atualizar referência de `link` e `unlink`).
- [ ] Passar todo o texto pelo gate da skill **`review-the-work`**: zero palavras banidas (*"powerful"*, *"seamless"*, *"revolutionary"*, *"best-in-class"*, *"platform"*), sem travessões artificiais de IA (*em-dashes*) nas narrativas de GTM, desenvolvedor como sujeito/herói das frases.

---

### US-007: Pivot da Landing Page (`spmx.io`), `StoreDiagram` e `CliSample` com `the-homepage` (`gtm-cofounder`)

**Description:** Como desenvolvedor iOS, macOS, Flutter ou React Native visitando `spmx.io`, eu quero entender em 5 segundos que o `spmx` unifica os pacotes SwiftPM da minha máquina inteira em um único store global por versão, ver a prova nos benchmarks e começar em 1 comando.

**Acceptance Criteria:**

- [ ] Reescrever `website/lib/site.ts` e `website/app/(home)/page.tsx` seguindo a estrutura e regras das skills **`the-homepage`**, **`positioning-and-story`**, **`value-prop-that-converts`** e **`review-the-work`**:
  - **Hero (`text-hero`):** Headline direta sobre o que é (*"One package store for every Swift project on your Mac."* / store global estilo pnpm/Puro para SwiftPM) + Subhead com o *Job-To-Be-Done* para quem tem múltiplos projetos, branches e worktrees + 2 CTAs claros (`Get started` e `View on GitHub` / `Docs`).
  - **Seção Problema (Vilão + Evento Incitante):** Mostrar que cada projeto no Xcode cria um `DerivedData/<App>-<Hash>/SourcePackages` isolado, baixando e duplicando gigabytes dos mesmos SDKs (`Firebase`, `Stripe`, `gRPC`, `SwiftSyntax`) em todo projeto e worktree da máquina.
  - **Seção Como Funciona (`StoreDiagram.tsx`):** Atualizar o SVG em `website/components/StoreDiagram.tsx` para ilustrar o `~/.spmx/store` no topo (com `firebase 1.0.0`, `firebase 1.0.1`, `stripe 3.4.5`, `xyz 4.0.0`, `abc 1.0.0`) clonando via `clonefile()` para **`project-a`**, **`project-b`** e **`project-c`** (além de worktrees).
  - **Terminal de Demonstração (`CliSample.tsx`):** Atualizar `website/components/CliSample.tsx` para demonstrar o fluxo multi-projeto e a linha de economia de espaço por projeto e global na máquina.
  - **Seção Workflow e Controle (`spmx setup`, `spmx link`, `spmx unlink`, `spmx status`):** Destacar que funciona automaticamente em toda a máquina, com opção simples de `spmx unlink` caso queira manter um projeto específico no cache local.
- [ ] **Design System (`website/app/globals.css`):** Utilizar exclusivamente os tokens existentes (`--color-paper`, `--color-paper-2`, `--color-ink`, `--color-ink-muted`, `--color-accent`, `--color-accent-text`, `--color-surface-warm`, `--color-line`, `--color-line-strong`, `--font-sans`, `--font-mono`) tanto no tema claro quanto escuro (`.dark`), mantendo suporte a `prefers-reduced-motion`.
- [ ] **Analytics (`docs/analytics-llm.md`):** Preservar os atributos e eventos existentes de PostHog (`captureEvent`) nos componentes interativos sem bloquear navegação.
- [ ] Build estático (`make site`) e checagem de contraste (`node website/scripts/check-contrast.mjs`) passam sem erros.
- [ ] **[UI Story]** Visualmente verificado no navegador em desktop e mobile (light e dark mode).

---

## 5. Functional Requirements

- **FR-1:** O `~/.spmx/store` deve armazenar e deduplicar `checkouts` por `(identity, revision)`, `repositories` bare por `identity`, `artifacts` por `(identity, targetName, checksum)` e `prebuilts` por `(toolchainHash, identity, versionOrChecksum)`.
- **FR-2:** Cortes iguais na mesma versão/revisão (ex.: `stripe 3.4.5` em `Projeto A` e `Projeto C`, ou `xyz 4.0.0` em `Projeto A` e `Projeto B`) devem existir como uma única instalação física no `~/.spmx/store` e ser materializados nos respectivos `SourcePackages` via APFS `clonefile()`.
- **FR-3:** Versões diferentes do mesmo pacote (ex.: `firebase 1.0.0` no `Projeto A` e `firebase 1.0.1` no `Projeto C`) devem coexistir lado a lado em `~/.spmx/store/checkouts/` e compartilhar o repositório Git bare em `~/.spmx/store/repositories/firebase-ios-sdk/`.
- **FR-4:** Quando um projeto possui apenas parte de suas dependências no `~/.spmx/store` (hidratação parcial), o `spmx hydrate` deve clonar os pacotes disponíveis e atualizar `workspace-state.json` + `repositories/` de modo que o SwiftPM baixe apenas os pacotes ausentes.
- **FR-5:** O `spmx harvest` deve recusar checkouts cujo working tree Git tenha modificações locais (`git status --porcelain != ""`) ou cujo `HEAD` divirja da revisão declarada.
- **FR-6:** Por padrão, qualquer projeto executado via shims (`swift`, `xcodebuild`, `flutter`) está vinculado ao store global, exceto quando o projeto estiver registrado em `excludedProjects` via `spmx unlink [path]` ou contiver um arquivo `.spmxignore`.
- **FR-7:** O comando `spmx unlink [path]` deve desvincular o projeto do store global para que ele utilize exclusivamente o cache local padrão do Xcode/SwiftPM.
- **FR-8:** Os comandos `spmx link [path]` e `spmx migrate [path]` devem aceitar um `<path>` opcional (default: máquina toda), exibir o resumo de projetos e espaço a ser economizado e exigir confirmação interativa `[y/N]` antes de executar (salvo quando `--yes` for informado).
- **FR-9:** O comando `spmx status` deve exibir o espaço aproximado economizado no projeto atual, e `spmx store status` / `spmx store list` devem exibir as versões semânticas, os projetos vinculados a cada versão e o espaço economizado por projeto e no global da máquina.

---

## 6. Non-Goals (Out of Scope)

- **Não alterar arquivos `Package.swift` ou `Package.resolved` do usuário** para forçar projetos diferentes a usarem a mesma versão: se o Projeto A pede `firebase 1.0.0` e o Projeto C pede `firebase 1.0.1`, ambos são respeitados exatamente nas suas versões.
- **Não substituir o resolvedor de versões do SwiftPM:** O SwiftPM continua resolvendo o grafo de versões; o `spmx` atua na camada de armazenamento, hidratação CoW e cache de compilação LLVM CAS.
- **Não gerenciar CocoaPods (`ios/Pods`) nem `node_modules`:** O escopo permanece estritamente em Swift Package Manager e cache de compilação Swift/Clang.
- **Não introduzir telemetria no binário CLI:** O CLI `spmx` permanece 100% offline e livre de telemetria (conforme [`docs/analytics-llm.md`](../docs/analytics-llm.md)).

---

## 7. Design Considerations (Website & Diagramas — `website/`)

- **Fonte do Design System:** [`website/app/globals.css`](../website/app/globals.css) (`designSystem: "use"` em [`tasks/.prd-generator.json`](./.prd-generator.json)).
- **Estilo e Direção Visual:** Editorial técnico minimalista, tipografia limpa (`--font-sans` Geist + `--font-mono` IBM Plex Mono), bordas nítidas (`--color-line`, `--color-line-strong`), divisor pixel-art (`.pixel-rule`) ecoando o ícone oficial [`assets/icon.svg`](../assets/icon.svg), sem gradientes genéricos de IA ou *puffery*.
- **Paleta de Cores (Tokens OKLCH de `globals.css`):**
  - Superfícies: `bg-paper` (`--color-paper`), `bg-paper-2` (`--color-paper-2`), `bg-surface-warm` (`--color-surface-warm`)
  - Texto: `text-ink` (`--color-ink`), `text-ink-muted` (`--color-ink-muted`)
  - Destaque / Marca: `stroke-accent` / `border-accent` (`--color-accent`), `text-accent-text` (`--color-accent-text`)
  - Semânticas: `text-ok` (`--color-ok`), `text-warn` (`--color-warn`), `text-err` (`--color-err`)
- **Componentes Existentes a Reutilizar:**
  - [`website/components/StoreDiagram.tsx`](../website/components/StoreDiagram.tsx) (atualizar nós de `worktree-a/b/c` para `project-a`, `project-b`, `project-c` mostrando o compartilhamento cruzado de versões)
  - [`website/components/CliSample.tsx`](../website/components/CliSample.tsx)
  - [`website/components/InstallTabs.tsx`](../website/components/InstallTabs.tsx), [`website/components/BenchBars.tsx`](../website/components/BenchBars.tsx), [`website/components/CommandCard.tsx`](../website/components/CommandCard.tsx), [`website/components/Faq.tsx`](../website/components/Faq.tsx)
- **Regras de UX e Acessibilidade:**
  - Contraste verificado via `node website/scripts/check-contrast.mjs`;
  - Animações SVG respeitando `@media (prefers-reduced-motion: reduce)`;
  - Responsividade de `375px` (mobile) a `1440px` (desktop) sem overflow horizontal (`overflow-x: clip`).

---

## 8. Technical Considerations

- **Fórmula de Espaço Economizado (`StoreManager` & `ProjectStatusInspector`):**
  - **Por projeto (`projectSavedBytes`):** Soma do tamanho em bytes de cada entrada em `SourcePackages/{checkouts,repositories,artifacts,prebuilts}` daquele projeto que está vinculada a uma entrada correspondente em `~/.spmx/store`.
  - **Global da máquina (`totalMachineSavedBytes`):** Para cada item único no store referenciado por $N \ge 1$ localizações hidratadas na máquina (projetos e worktrees), cada clone CoW evita uma cópia física adicional no `DerivedData` do projeto. A visão por projeto mostra quanto cada projeto deixou de ocupar de forma independente, e o sumário global mostra tanto a soma dos projetos hidratados quanto a economia líquida frente ao tamanho único do `~/.spmx/store`.
- **Segurança na Varredura da Máquina Toda (`spmx link` / `spmx migrate`):**
  - Ao rodar sem `<path>` (default máquina toda), o scanner deve buscar em `~/Library/Developer/Xcode/DerivedData` e nas pastas de trabalho do usuário dentro de `~`, **excluindo obrigatoriamente** diretórios lentos ou protegidos pelo TCC do macOS (`~/Library` exceto `DerivedData`, `~/.Trash`, `~/Pictures`, `~/Music`, `~/Movies`, `/System`, `/Volumes`, `node_modules`, `.git`, `.build`, `Pods`, `~/.spmx`).
- **Conformidade com Analytics (`docs/analytics-llm.md`):**
  - Qualquer novo CTA ou comando copiável na landing page deve usar `CopyButton` / `captureEvent` existente, mantendo o modelo *personless* e *non-blocking*.

---

## 9. Success Metrics

- **100% de reaproveitamento entre projetos distintos:** No cenário `Projeto A`, `Projeto B`, `Projeto C`, os pacotes em comum na mesma versão (`stripe 3.4.5`, `xyz 4.0.0`) têm **0 bytes baixados da rede** no segundo projeto e são hidratados em `< 500ms` via `clonefile()`.
- **0 falsos positivos de corrupção:** Checkouts modificados localmente nunca são colhidos para o `~/.spmx/store`, e projetos desvinculados com `spmx unlink` operam 100% isolados no cache local.
- **Clareza imediata de valor (Time to First Value < 2 min):** Ao rodar `spmx setup && spmx link` (ou `spmx status`), o desenvolvedor vê imediatamente os projetos encontrados na máquina e o total de MB/GB economizados por projeto e no global.
- **Aprovação no gate `review-the-work` (`gtm-cofounder`):** Landing page (`spmx.io`) e `README.md` livres de *puffery*, com o desenvolvedor como herói, problema antes da solução, e Lighthouse CI $\ge 95$ em Performance/Accessibility/Best Practices/SEO.

---

## 10. Self-Check Gate (`review-the-work` Audit)

- **Verdict:** **PASS**
- **Checagens executadas:**
  - *Sem puffery?* Sim — removidos termos vagos como "powerful", "seamless", "revolutionary"; substituídos pelo mecanismo real (`APFS clonefile()`, deduplicação por `(package, version)`, números reais de `spmx.io/benchmarks`).
  - *Desenvolvedor é o herói e existe um vilão real?* Sim — o vilão é a multiplicação de SDKs multi-gigabyte em cada `DerivedData/<App>-<Hash>` isolado do Xcode; o dev resolve isso na máquina inteira em um comando.
  - *Ponto mais fraco identificado (honestidade cética):* Como o projeto ainda está em `0 usuários externos entrevistados` (`[assumption]` no `founder-brief.md`), a dor multi-projeto foi validada primeiro no workflow do próprio fundador. O próximo passo do `gtm-roadmap.md` após implementar este PRD é rodar `talk-to-users` com 5–10 devs iOS/Flutter para coletar números reais de GB economizados nas máquinas deles e adicioná-los como prova atribuída no site.

---

## 11. Open Questions

Nenhuma decisão pendente — escopo técnico, comandos CLI (`spmx link [path]`, `spmx unlink [path]`, `spmx status`, `spmx store list`, `spmx store status`) e posicionamento GTM confirmados.
