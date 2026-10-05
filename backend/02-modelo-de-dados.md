# 02 — Modelo de dados

Fonte: `core/models.py`. Todas as entidades herdam de `BaseModel`.

## 1. BaseModel (abstrato)

| Campo | Tipo | Observação |
|-------|------|------------|
| `id` | BigAutoField (PK) | Inteiro autoincrementado |
| `created_at` | DateTime | `default=timezone.now`, não editável |
| `updated_at` | DateTime | `auto_now` |
| `is_active` | Boolean | Default `True` |

Managers: `objects` (todos) e `active` (somente `is_active=True`).

## 2. Diagrama de relacionamentos

```
Company 1─* Person 1─1 AccessAccount
   │  └──* Vehicle *─1 Person(DRIVER)
   │  └──* Route *─0..1 Vehicle
   │  │      ├──* RouteStop *─1 MeetingPoint *─1 Address
   │  │      ├──* RoutePassenger *─1 Person(EMPLOYEE)   (opcional: *─1 RouteStop)
   │  │      └──* RouteEvent
   │  └──* Schedule
   │  └──* MeetingPoint
   └──* Address (company e/ou person, ambos opcionais)
Person 1─* Address
```

## 3. Entidades

### Company
| Campo | Tipo | Regras |
|-------|------|--------|
| `name` | Char(255) | obrigatório |
| `email_domain` | Char(255) | opcional; normalizado (minúsculas, sem `@`). Vazio ⇒ derivado do nome |

`get_email_domain()`: usa `email_domain` ou deriva `<primeira-palavra-alfanumérica>.com` do nome (fallback `empresa.com`).

### Person
| Campo | Tipo | Regras |
|-------|------|--------|
| `company` | FK Company (CASCADE, `people`) | obrigatório |
| `name` | Char(255) | obrigatório |
| `phone` | Char(30) | obrigatório |
| `type` | Char(20), indexado | `DRIVER` \| `EMPLOYEE` |
| `license_number` | Char(100), null | obrigatório se DRIVER; proibido se EMPLOYEE |
| `employee_code` | Char(100), null | obrigatório se EMPLOYEE; proibido se DRIVER |

- `save()` chama `full_clean()` (validação sempre executada).
- `get_auto_email()` = `{employee_code|license_number, minúsculo, sem espaços}@{domínio da empresa}`.

### AccessAccount
| Campo | Tipo | Regras |
|-------|------|--------|
| `person` | OneToOne Person (CASCADE, `access_account`) | |
| `email` | Email, único, indexado | normalizado (trim + minúsculas) |
| `role` | Char(20), choices `DRIVER`/`EMPLOYEE`/`MANAGER`, indexado | default `EMPLOYEE`; nasce `DRIVER` para pessoa DRIVER. `DRIVER` só para pessoa DRIVER; `EMPLOYEE`/`MANAGER` só para pessoa EMPLOYEE (`AccessAccount.validate_role()`, chamado em `save()` e `clean()`). `MANAGER` dá acesso ao CRUD administrativo e ao painel |
| `password_hash` | Char(255) | hash Django (`make_password`) |
| `must_change_password` | Boolean | default `True` |
| `failed_login_attempts` | Integer | default 0 |
| `last_login` | DateTime, null | |
| `blocked_until` | DateTime, null | bloqueio temporário |
| `password_reset_code_hash` | Char(255) | hash do OTP |
| `password_reset_expires_at` | DateTime, null | |
| `password_reset_requested_at` | DateTime, null | |
| `password_reset_code_used` | Boolean | default `True` |

### Address
| Campo | Tipo |
|-------|------|
| `company` | FK Company, null/blank (`addresses`) |
| `person` | FK Person, null/blank (`addresses`) |
| `street` Char(100), `number` Char(20), `city` Char(50), `state` Char(50), `zip_code` Char(10) | obrigatórios |
| `latitude`, `longitude` | Decimal(9,6) obrigatórios |

### MeetingPoint
`company` (FK, `meeting_points`), `name` Char(255), `address` (FK Address, CASCADE, `meeting_points`).

### Vehicle
| Campo | Tipo | Regras |
|-------|------|--------|
| `company` | FK Company, null/blank (`vehicles`) | |
| `driver` | FK Person, SET_NULL, null/blank (`vehicles`) | `limit_choices_to type=DRIVER` |
| `plate_number` | Char(20) | **único** |
| `model` | Char(100) | |
| `capacity` | PositiveInteger | |

### Route
`company` (FK, `routes`), `name` Char(255), `vehicle` (FK Vehicle, SET_NULL, null/blank, `routes`). O motorista da rota é `route.vehicle.driver`.

### RouteStop
| Campo | Regras |
|-------|--------|
| `route` | FK Route (CASCADE, `stops`) |
| `meeting_point` | FK MeetingPoint (CASCADE, `route_stops`) |
| `sequence` | PositiveSmallInteger; `0` = primeiro ponto |

- Ordenação padrão por `sequence`.
- Constraint `UNIQUE(route, sequence)` (`core_routestop_unique_route_sequence`).
- `clean()`: o ponto de encontro deve ser da mesma empresa da rota. `save()` chama `full_clean()`.

### Schedule
`company` (FK, `schedules`), `weekdays` JSON (lista), `time` Time.

### RoutePassenger
| Campo | Regras |
|-------|--------|
| `person` | FK Person (CASCADE), `limit_choices_to EMPLOYEE`, indexado |
| `route` | FK Route (CASCADE, `route_passengers`), indexado |
| `route_stop` | FK RouteStop, SET_NULL, null/blank (`passengers`) |
| `boarding_status` | `pending` (default) \| `confirmed` \| `absent`; indexado |

- `UNIQUE(person, route)` e índice `(person, route)`.
- `clean()`: se houver `route_stop`, ele deve pertencer à mesma rota. `save()` chama `full_clean()`.

### RouteEvent
| Campo | Regras |
|-------|--------|
| `route` | FK Route (CASCADE, `events`) |
| `event_type` | `departure` \| `arrival` \| `stop` \| `delay` \| `incident` |
| `description` | Text, opcional (obrigatória na API para `delay`/`incident`) |
| `latitude`, `longitude` | Decimal(9,6) |
| `timestamp` | `auto_now_add` |

## 4. Observações

- Não há `Meta.ordering` global (exceto `RouteStop`); a listagem usa a ordem natural do banco, exceto `RouteEvent` (ordenado por `-timestamp` na API).
- Os relacionamentos usam CASCADE na maioria dos casos: excluir `Company` remove pessoas, rotas, veículos, horários etc.
- Os filtros de "ativos" aplicam-se somente na leitura (`BaseViewSet.get_queryset`); ver `05-regras-de-negocio.md`.
