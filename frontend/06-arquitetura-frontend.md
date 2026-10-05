# 06 — Arquitetura do frontend

Aplicação Angular 19 com **standalone components**, roteamento lazy por domínio, Angular Material e PrimeFlex. Fontes: `src/app/**`, `package.json`.

## 1. Bootstrap e providers (`app.config.ts`)

| Provider | Função |
|----------|--------|
| `provideZoneChangeDetection({ eventCoalescing: true })` | Change detection com coalescência de eventos |
| `provideAnimations()` | Animações do Material |
| `provideHttpClient(withInterceptors([authInterceptor]), withInterceptorsFromDi())` | HttpClient com o interceptor funcional de token e os interceptors via DI |
| `provideAppInitializer(...)` | Carrega `assets/config/config.json` antes de iniciar (`ConfigService.loadConfig()`) |
| `MatPaginatorIntl` customizado | Rótulos em português ("Itens por página:", "1 - 10 de 42") |
| `HTTP_INTERCEPTORS` → `DeduplicateRequestsInterceptor` | Deduplicação de requests |
| `provideRouter(routes)` | Roteamento |

## 2. Configuração de ambiente

`ConfigService` lê `assets/config/config.json`:

```json
{ "apiBaseUrl": "http://<host>:8000/api" }
```

- `getApiBaseUrl()` retorna a URL base (string vazia se a leitura falhar; erro apenas logado).
- `environments/environment.ts` define `apiUrl` (`http://${location.hostname}:8000`) mas **não é usado** pelos serviços; a fonte de verdade é o `config.json`.
- `app.urls.ts` declara `URLS.COMPANY` e `URLS.EMPLOYEE` (`api/companies`, `api/employees`), sem uso nos serviços atuais.

## 3. Camada de serviços

### `BaseService<T>` (abstrato, `core/services/base.service.ts`)

Cada serviço de domínio herda e define `endpoint`. URL final: `{apiBaseUrl}/{endpoint}/`.

| Método | HTTP | URL |
|--------|------|-----|
| `getAll(params?)` | GET | `/{endpoint}/?…` (params vazios/nulos são omitidos) |
| `getById(id)` | GET | `/{endpoint}/{id}/` |
| `create(data)` | POST | `/{endpoint}/` |
| `update(id, data)` | PUT | `/{endpoint}/{id}/` |
| `patch(id, data)` | PATCH | `/{endpoint}/{id}/` |
| `delete(id)` | DELETE | `/{endpoint}/{id}/` |

Todos registram a requisição via `console.debug` e erros via `console.error`, e repropagam o erro. **Não há tratamento de token, refresh ou erros 401/403.**

### Serviços por domínio

| Serviço | `endpoint` | Observação |
|---------|-----------|-----------|
| `CompanyService` | `companies` | |
| `EmployeeService` | `people` | Usado tanto para funcionários quanto motoristas (tipo escolhido no formulário) |
| `VehicleService` | `vehicles` | |
| `RouteService` | `routes` | |
| `ScheduleService` | `schedules` | |
| `RouteEventService` | `route-events` | |

## 4. Autenticação (`core/`)

| Peça | Função |
|------|--------|
| `models/auth.model.ts` | `Role` (`DRIVER`/`EMPLOYEE`/`MANAGER`), `ROLE_LABELS`, `SessionPerson`, `LoginResponse`, `MeResponse` |
| `services/auth.service.ts` | Estado da sessão em *signals* (`person`, `isAuthenticated`, `isManager`, `mustChangePassword`), persistido em `localStorage` (`rotacerta.session`, com `try/catch`). `login`, `changePassword`, `refreshAccessToken` (uma renovação em voo compartilhada), `ensureProfile` (`GET auth/me/` uma vez por carga), `logout` |
| `interceptors/auth.interceptor.ts` | Anexa `Authorization: Bearer` às chamadas da API (exceto `auth/login`, `refresh`, `verify`, `password-reset`). Em 401: renova o access token e **repete** a requisição; se a renovação falhar, encerra a sessão e vai ao login. Erros da requisição repetida seguem ao chamador |
| `guards/auth.guard.ts` | `managerGuard` (sessão + perfil `MANAGER` confirmado no servidor + senha já trocada; outro perfil é deslogado e volta ao login com aviso), `authenticatedGuard` (troca de senha), `guestGuard` (login) |
| `features/auth/` | `LoginComponent` (`/login`) e `ChangePasswordComponent` (`/alterar-senha`, obrigatória enquanto `must_change_password`) |

O painel é **exclusivo de gestores**: motorista/funcionário que autentica corretamente é recusado na tela e nenhuma sessão é guardada. A checagem de perfil no cliente é só experiência de uso; a barreira real é a API (`IsManager`).

## 5. Interceptor de deduplicação

`DeduplicateRequestsInterceptor` mantém um mapa de requisições em andamento, com chave `MÉTODO::URL+params::body(JSON)`. Requisição idêntica enquanto outra está em voo reutiliza o mesmo observable (`shareReplay(1)`); a entrada é removida ao terminar (sucesso, erro ou complete). Evita chamadas duplicadas, por exemplo várias telas pedindo `companies/` ao mesmo tempo.

## 5. Utilitários e DTOs compartilhados

- `IPaginatedResultDto<T>`: `{ count, next, previous, results }`.
- `extractPaginatedItems(response)`: aceita array, `{results}` ou `{value}`.
- `extractPaginatedCount(response, fallback)`: usa `count`/`Count` ou o tamanho da lista.
- `DialogComponent` (Material Dialog de confirmação, retorna `true/false`); ainda **não usado** — as exclusões usam `confirm()` nativo.

## 6. Padrão de componentes

Cada domínio segue o mesmo modelo:

- **`*-list`**: `MatTable` + `MatPaginator` com paginação server-side (`page`, `page_size`), botões Novo/Editar/Excluir. Carrega dados no `ngOnInit`; exclusão com `window.confirm`, seguida de recarga.
- **`*-detail`**: `ReactiveForms` compartilhado entre criação e edição. Modo edição quando existe `:id` na rota (`isEdit`). Salva com `POST` (novo) ou `PATCH` (edição) e navega de volta à lista.
- **Modelos** em `models/*.ts` e serviço em `service(s)/`.

As listas de Funcionários, Rotas e Eventos de rota aplicam `debounceTime(250)` na troca de página. Listas e formulários carregam dados auxiliares (empresas, veículos, rotas) com `getAll()` **sem parâmetros**, portanto apenas a primeira página (10 itens) da API.

## 7. Layout

- `AppMenuComponent` (rota-pai `''`, protegida por `managerGuard`): `mat-toolbar` superior (marca "Rotacerta", atalhos, **usuário logado**: nome, "Gestor · empresa", iniciais e botão *Sair*, vindos do `AuthService`), `mat-drawer` lateral com seções PRINCIPAL / GESTÃO / CONFIG e `<router-outlet>`.
- `HomeComponent`: tela de boas-vindas; título/descrição vêm de `route.data` (padrão "Bem-vindo(a)!").
- `ReportMaintenanceComponent`: tela "em manutenção" reutilizada em Dashboard, Mapa, Configurações e Relatórios; lê título/descrição de `route.data`.
- `DashboardComponent`: existe (cards de exemplo com data fixa) mas **não está roteado**.

## 8. Dependências principais

Angular 19 (`animations, cdk, common, compiler, core, forms, material, platform-browser(-dynamic), router`), `primeflex ^4`, `rxjs ~7.8`, `zone.js ~0.15`, TypeScript `~5.6`. Testes: Karma + Jasmine (existem `*.spec.ts` apenas para `employee-list`, `employee-detail` e `dashboard`).
