# 01 — Arquitetura

## 1. Visão de componentes

```
┌──────────────────────┐      HTTP/JSON       ┌───────────────────────────┐
│ Frontend Angular 19  │ ───────────────────► │ Backend Django 5.2 + DRF  │
│ (SPA, Material)      │  apiBaseUrl (config) │ app `core` sob /api/      │
└──────────────────────┘                      └────────────┬──────────────┘
┌──────────────────────┐      HTTP/JSON                    │
│ App Android (Kotlin) │ ───────────────────────────────►  │ ORM
└──────────────────────┘                                   ▼
                                              ┌────────────────────────┐
                                              │ PostgreSQL (ou SQLite) │
                                              └────────────────────────┘
                              Backend ──► Google Routes API (navegação do motorista)
```

## 2. Stack

| Camada | Tecnologia | Versão (do código) |
|--------|-----------|--------------------|
| Backend | Django | 5.2.8 |
| | Django REST Framework | 3.16.1 |
| | djangorestframework-simplejwt | 5.5.1 |
| | django-filter | 25.2 |
| | drf-spectacular (OpenAPI) | 0.29.0 |
| | django-cors-headers | 4.9.0 |
| | python-decouple | 3.8 |
| | psycopg2-binary | 2.9.10 |
| Banco | PostgreSQL (produção/dev) ou SQLite (fallback) | — |
| Frontend | Angular (standalone components) | 19 |
| | Angular Material / CDK | 19.2.x |
| | PrimeFlex | 4 |
| | RxJS / TypeScript | 7.8 / 5.6 |
| | Testes | Jasmine + Karma |

## 3. Backend

- Projeto Django `config` (settings, urls, wsgi/asgi) e uma única app `core`.
- Roteamento: `config/urls.py` expõe `admin/` e `api/` → `core/urls.py`.
- `core/urls.py` registra um `DefaultRouter` com 12 viewsets e 7 rotas `auth/*`.
- Camadas em `core/`: `models.py` → `serializers.py` / `driver_serializers.py` / `auth_serializers.py` → `viewsets.py` / `auth_views.py`; `filters.py` (django-filter), `permissions.py`, `authentication.py`, `tokens.py`, `signals.py`.
- Comandos de gestão: `ensure_access_accounts`, `reset_initial_access_passwords`, `seed_manaus_demo`.
- Migrações: `0001_initial` … `0005_driver_route_stops`.

## 4. Frontend

Estrutura sob `src/app/`:

| Pasta | Responsabilidade |
|-------|------------------|
| `core/` | `BaseService<T>` (CRUD HTTP), `ConfigService` (carrega `assets/config/config.json`), `DeduplicateRequestsInterceptor` |
| `features/<domínio>/` | `components/` (list/detail), `models/`, `service(s)/`, `<dominio>.routes.ts` (lazy) |
| `layout/` | `app-menu` (shell com toolbar + drawer), `home`, `dashboard` (não roteado) |
| `shared/` | `dialog`, DTO de paginação, utilitários de resposta paginada |

Domínios: `company`, `employee`, `vehicle`, `route`, `schedule`, `route-event`, `report` (placeholder).

## 5. Fluxo típico (listagem paginada)

1. Componente chama `service.getAll({ page, page_size })`.
2. `BaseService` monta `GET {apiBaseUrl}/{endpoint}/` com query params (vazios são descartados).
3. `DeduplicateRequestsInterceptor` reaproveita requisições idênticas em andamento.
4. DRF responde `{ count, next, previous, results }` (`PageNumberPagination`, 10 por página).
5. `extractPaginatedItems/Count` normalizam a resposta (aceita array, `results` ou `value`).

## 6. Requisitos não funcionais observados

- **RNF-01** CORS liberado para qualquer origem (`CORS_ALLOW_ALL_ORIGINS = True`).
- **RNF-02** Throttling DRF: `anon` 100/hora, `user` 1000/hora (o frontend web não autentica, então suas chamadas contam como `anon`).
- **RNF-03** Paginação padrão de 10 itens.
- **RNF-04** Configuração por variáveis de ambiente (`python-decouple`).
- **RNF-05** Documentação OpenAPI via drf-spectacular (configurada; rotas de schema/UI não estão expostas em `urls.py`).
- **RNF-06** `USE_TZ = True`, `TIME_ZONE = UTC`, `LANGUAGE_CODE = en-us`.
