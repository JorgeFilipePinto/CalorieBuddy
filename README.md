# CalorieBuddy

App iOS em SwiftUI do atleta da plataforma **IronMan Project**. Serve para registar nutrição (diário, catálogo de alimentos, receitas, plano alimentar, objetivos por tipo de dia), suplementos e stocks, preços por loja e dados da app Saúde (peso, água, café, sono, treinos e recordes pessoais).

A app é **offline-first**: tudo é guardado localmente num ficheiro JSON. Opcionalmente, sincroniza com o Supabase da plataforma, onde a nutricionista e o treinador acompanham os dados no dashboard web.

## Funcionalidades

- **Diário**: 7 formas de registar:
  - manual;
  - scanner de código de barras;
  - do catálogo;
  - do plano alimentar;
  - receita;
  - suplemento;
  - JSON gerado por IA.

  Os totais de kcal e macros são comparados com os objetivos do plano em vigor.
- **Objetivos por tipo de dia**: planos nutricionais com data de início e metas diferentes para dias de treino e de descanso. Um dia com treino na app Saúde usa as metas de treino.
- **Plano alimentar**: refeições com opções ligadas a receitas. Ao registar uma opção, os alimentos podem ser trocados por equivalentes do mesmo macro dominante e as quantidades ajustadas.
- **Biblioteca**:
  - catálogo de alimentos (por 100 g/ml ou por dose, minerais e vitaminas, vários códigos de barras);
  - receitas;
  - lojas e preços (com promoções), para estimar o custo por dose ou receita;
  - suplementos com stock por local e notificação de stock baixo.
- **Saúde e treino** (HealthKit):
  - peso, massa gorda, IMC, água, café, sono e calorias;
  - gráfico de evolução multi-métrica;
  - **recordes pessoais** por distância, com previsões para Ironman 70.3 e Ironman (fórmula de Riegel).
- **Plataforma**:
  - login como atleta;
  - sincronização incremental (planos nos dois sentidos, diário, catálogo e app Saúde a subir);
  - backup completo e restauro;
  - estatísticas de uso sem dados de saúde.
- **Dados do utilizador**: export, import, backup, restauro e edição do JSON dentro da app, e eliminação total.

A interface está em português (pt-PT).

## Requisitos

- Xcode com o SDK iOS 27 (deployment target 27.0, iOS e macOS)
- Para a sincronização: o projeto Supabase da plataforma IronMan Project, local (Docker + Supabase CLI) ou no VPS

Não há dependências de pacotes.

## Começar

```bash
git clone git@github.com:JorgeFilipePinto/CalorieBuddy.git
cd CalorieBuddy
open CalorieBuddy.xcodeproj
```

Ou pela linha de comandos:

```bash
xcodebuild -project CalorieBuddy.xcodeproj -scheme CalorieBuddy -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build
```

O HealthKit e o scanner só funcionam em iOS. No macOS, essas funcionalidades ficam desativadas.

### Ligar à plataforma (opcional)

Sem configuração, a app funciona normalmente e o ecrã da plataforma indica que a sincronização não está disponível.

1. Copia `Config/Supabase.example.plist` para:
   - `MyApp/Resources/Config/Supabase-Debug.plist`: Supabase local. O URL e a key estão em `supabase status -o env`. Use `http://127.0.0.1:54321` no Simulador ou `http://<mac>.local:54321` num iPhone na mesma rede.
   - `MyApp/Resources/Config/Supabase-Release.plist`: o VPS de produção.
2. Preenche o **URL** e a **publishable key**. Estes ficheiros estão no `.gitignore`. **Nunca coloques a secret / service_role key na app**: o acesso é controlado pela Row Level Security.
3. Na app: **Definições → Plataforma e Sincronização → Iniciar Sessão**, com a conta de **atleta** da plataforma. Só este papel pode escrever dados.

## Arquitetura

```
MyApp/
├── App/          Entrada (@main), fases de arranque, TabView
├── Core/
│   ├── Models/       Entidades Codable (AppDatabase e todos os modelos)
│   ├── Persistence/  DataStore (fonte de verdade) + Seeds/
│   ├── Health/       HealthKitManager
│   ├── Platform/     SupabaseClient, PlatformSync, AppAnalytics
│   └── Import/       Parsing de JSON gerado por IA
├── Features/     Um folder por área: Intro, Day, History, Health,
│                 Library (Catalog, Recipes, Stores, Supplements, Stocks),
│                 Plans, Settings
├── Shared/       Componentes e utilitários usados por várias features
└── Resources/    Assets, vídeo da intro, Config/*.plist
```

- **Três singletons `@Observable`** criados em `MyApp.swift` e injetados com `.environment(...)`:
  - `DataStore`: todos os dados da app;
  - `HealthKitManager`: app Saúde;
  - `PlatformSyncManager`: sincronização.
- **Persistência**: o estado inteiro é um `AppDatabase` gravado como JSON em `Application Support/CalorieBuddy/active_database.json`.
  - Não há botão "guardar": todo o método que altera dados termina em `persistActive()`.
  - Imports e restauros guardam o estado anterior em `backup_database.json`.
- **Sincronização** (`URLSession`, sem SDK), por esta ordem:
  1. planos nutricionais nos dois sentidos (ganha a edição mais recente);
  2. dados da app para `app_documents` (backup sem perdas), mais `food_entries` / `food_items` para o dashboard, de forma incremental por hash e com soft deletes;
  3. app Saúde por janelas, através de RPCs que substituem a janela inteira;
  4. eventos de uso;
  5. registo da sincronização.

  Corre automaticamente quando a app vai para background e quando volta a abrir (no máximo de 15 em 15 min), e também manualmente.
- **Sessão** no Keychain, com refresh automático do access token.

### Convenções

- Os novos `.swift` vão para a pasta da sua responsabilidade dentro de `MyApp/`. O projeto usa um grupo sincronizado com o sistema de ficheiros, por isso não é preciso editar o `project.pbxproj`.
- Coleções e campos novos no modelo descodificam com `decodeIfPresent(...) ?? []`, para que os exports antigos continuem a carregar. Uma coleção nova também tem de entrar em `AppCollection.all(of:)` e em `restore(into:)`.
- O código só de iOS fica protegido com `#if canImport(HealthKit) && os(iOS)` (e equivalentes), com no-ops no macOS.
- Os eventos de analytics nunca levam valores nutricionais, medidas corporais nem dados da app Saúde.
- O texto visível é em português (pt-PT); o código e os comentários são em inglês.

## Privacidade

- Os dados ficam no dispositivo até iniciares sessão na plataforma.
- A sincronização vai apenas para o Supabase da própria plataforma, e quem vê os dados é decidido pela RLS: o atleta, a nutricionista e o treinador.
- As estatísticas de uso podem ser desligadas em **Definições → Plataforma e Sincronização**.
