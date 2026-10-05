# 03 — API REST

Base: `/api/`. Formato: JSON. Fontes: `core/urls.py`, `core/viewsets.py`, `core/serializers.py`, `core/filters.py`.

## 1. Convenções gerais

- **Paginação**: `PageNumberPagination`, `PAGE_SIZE = 10`, parâmetro `?page=N`. Resposta: `{ "count", "next", "previous", "results": [] }`. **Não há `page_size` configurável** (o frontend envia `page_size`, que é ignorado — ver `10-lacunas-e-melhorias.md`).
- **Filtros**: `django-filter` (`filterset_class` por recurso). `BaseViewSet` fixa `filter_backends = [DjangoFilterBackend]`, portanto `SearchFilter`/`OrderingFilter` (globais no settings) **não** se aplicam, exceto em `route-events/`, que declara `OrderingFilter` (`?ordering=`). `addresses/` não possui filterset.
- **Listagem** retorna somente registros com `is_active=True`. Detalhe (`GET /{id}/`) também é filtrado por `is_active=True`.
- **DELETE** remove o registro do banco (não é soft delete).
- **Campos base** em todas as respostas: `id`, `created_at`, `updated_at`, `is_active`.
- **Barra final** obrigatória nas URLs (`/api/companies/`).
- **Permissões**: nenhuma classe padrão configurada; ver `04-autenticacao-e-seguranca.md`.

## 2. CRUD (ModelViewSet)

Todos suportam `GET` lista, `POST`, `GET/PUT/PATCH/DELETE /{id}/`.

| Recurso | Endpoint | Filtros (`?`) | Observações |
|---------|----------|---------------|-------------|
| Empresas | `companies/` | `name` (icontains), `is_active` | |
| Pessoas | `people/` | `company_id`, `type`, `is_active` | Resposta inclui `auto_email` e `company_name` |
| Motoristas | `drivers/` | `company_id`, `is_active` | Somente `type=DRIVER`; campos: `id, company, company_name, name, phone, license_number, created_at` |
| Funcionários | `employees/` | `company_id`, `is_active` | Somente `type=EMPLOYEE`; campos: `id, company, company_name, name, phone, employee_code, created_at` |
| Rotas | `routes/` | `company_id`, `vehicle_id`, `name` (icontains), `is_active` | Campos `company`, `vehicle` como IDs |
| Paradas de rota | `route-stops/` | `route_id`, `is_active` | Leitura: `meeting_point` aninhado; escrita: `meeting_point_id` |
| Horários | `schedules/` | `company_id`, `is_active` | `weekdays` = lista JSON |
| Endereços | `addresses/` | — | |
| Pontos de encontro | `meeting-points/` | `company_id`, `city` (icontains em `address__city`), `is_active` | Leitura: `address` aninhado; escrita: `address_id` |
| Passageiros de rota | `route-passengers/` | `route_id`, `person_id`, `boarding_status`, `is_active` | Leitura: `person`/`route_stop` aninhados; escrita: `person_id`, `route_stop_id` |
| Eventos de rota | `route-events/` | `route_id`, `event_type` (lista separada por vírgula, `in`) | Ordenável por `timestamp`, `event_type`; padrão `-timestamp` |
| Veículos | `vehicles/` | `company_id`, `driver_id`, `plate_number`, `model` (icontains), `min_capacity`, `max_capacity`, `is_active` | Leitura: `driver` aninhado (Person); escrita: `driver_id` |

### 2.1 Exemplos de payload

**Company** (POST)
```json
{ "name": "Samsung", "email_domain": "samsung.com", "is_active": true }
```

**Person** (POST `people/`)
```json
{ "company": 1, "name": "Ana Souza", "phone": "92992281234",
  "type": "EMPLOYEE", "employee_code": "101010", "license_number": null }
```

**Vehicle** (POST) — o motorista deve ser enviado como `driver_id`
```json
{ "company": 1, "driver_id": 7, "plate_number": "ABC1D23", "model": "Marcopolo", "capacity": 40 }
```

**RouteStop** (POST)
```json
{ "route": 3, "meeting_point_id": 5, "sequence": 0 }
```

**RoutePassenger** (POST)
```json
{ "route": 3, "person_id": 12, "route_stop_id": 9, "boarding_status": "pending" }
```

**RouteEvent** (POST)
```json
{ "route": 3, "event_type": "delay", "description": "Trânsito intenso",
  "latitude": "-3.119027", "longitude": "-60.021731" }
```

**Schedule** (POST)
```json
{ "company": 1, "weekdays": ["MON","TUE","WED","THU","FRI"], "time": "07:30:00" }
```

## 3. Endpoints do app do motorista (`routes/`)

Exigem `IsAuthenticated` e `IsDriver` (`role == DRIVER`), exceto `events`, que também aceita gestor (o motorista só vê rotas dele; de outro motorista responde 404).

| Endpoint | Descrição |
|----------|-----------|
| `GET routes/my-routes/` | Rotas ativas cujo `vehicle.driver` é o motorista autenticado. **Retorna array simples (sem paginação).** |
| `GET routes/{id}/driver-detail/` | Mesmo formato para uma rota; 404 se não pertencer ao motorista |
| `GET routes/{id}/events/` | Eventos da rota (`-timestamp`), sem paginação |
| `GET routes/{id}/navigation/` | Calcula rota no Google Routes API |

**Payload de `my-routes` / `driver-detail`** (`DriverRouteBoardSerializer`):
```json
{
  "id": 3, "name": "Rota Zona Leste", "company_id": 1, "company_name": "Samsung",
  "vehicle": { "id": 2, "plate_number": "ABC1D23", "model": "Marcopolo" },
  "route_status": "waiting | in_route | delayed",
  "eta_next_stop": null,
  "stops": [ { "id": 9, "sequence": 0, "title": "Ponto A", "subtitle": "Rua X, 10 — Manaus/AM",
               "latitude": "-3.1", "longitude": "-60.0", "passenger_count": 4 } ],
  "passengers": [ { "id": 21, "person_id": 12, "name": "Ana", "point": "Ponto A",
                    "status": "pending", "route_stop_id": 9 } ]
}
```
`route_status` deriva do último evento: nenhum ⇒ `waiting`; `delay`/`incident` ⇒ `delayed`; `departure` ⇒ `in_route`; demais ⇒ `waiting`.

**`navigation`** — resposta 200:
```json
{ "route": 3, "encoded_polyline": "...", "duration": "1234s", "duration_text": "21 min",
  "distance_meters": 15400, "distance_text": "15.4 km", "instruction": "Siga a rota",
  "waypoints": { "origin": {"latitude":0,"longitude":0},
                 "intermediates": [], "destination": {"latitude":0,"longitude":0} } }
```
Erros: `403` (não é motorista), `404` (rota não é do motorista), `400` (origem/destino sem coordenadas), `502` (falha/indisponibilidade do Google), `503` (`GOOGLE_MAPS_API_KEY` ausente).

## 4. Perfis e permissões por recurso

`DEFAULT_PERMISSION_CLASSES = [IsAuthenticated]`. Sem token ⇒ `401`; token de perfil sem permissão ⇒ `403`.

| Recurso | `MANAGER` | `DRIVER` | `EMPLOYEE` |
|---------|-----------|----------|------------|
| `companies`, `people`, `drivers`, `employees`, `routes`, `route-stops`, `schedules`, `addresses`, `meeting-points`, `vehicles` (CRUD) | total, todas as empresas | 403 | 403 |
| `people/{id}/access-role/` (`POST {"role":"EMPLOYEE"\|"MANAGER"}`) | sim; 400 para motorista, pessoa sem conta, ou ao remover o **próprio** perfil de gestor | 403 | 403 |
| `route-events/` | total | `GET` e `POST`, só de rotas cujo `vehicle.driver` é ele (criar em rota alheia ⇒ 403; ler ⇒ 404); sem `PUT/PATCH/DELETE` | 403 |
| `route-passengers/` | total | `GET` e `PATCH` só de passageiros das próprias rotas, e **apenas** `boarding_status` (outro campo ⇒ 403); sem `POST/PUT/DELETE` | 403 |
| `routes/my-routes`, `driver-detail`, `navigation` | 403 | sim | 403 |
| `routes/{id}/events/` | sim | só das próprias rotas | 403 |
| `auth/me/`, `auth/change-password/` | sim | sim | sim |

`PersonSerializer` inclui `role` (somente leitura; `null` se a pessoa não tem conta).

## 5. Endpoints de autenticação

Ver `04-autenticacao-e-seguranca.md` (`auth/login/`, `auth/me/`, `auth/refresh/`, `auth/verify/`, `auth/change-password/`, `auth/password-reset/{request,verify,reset}/`).

## 5. Validações relevantes por recurso

| Recurso | Regra |
|---------|-------|
| Person / Driver / Employee | Regra de tipo (`license_number` × `employee_code`); `type` forçado pelo serializer especializado |
| Vehicle | `driver_id` deve existir e ser `DRIVER` |
| RoutePassenger | `person_id` deve ser `EMPLOYEE`; `route_stop_id` deve pertencer à `route` informada; `unique(person, route)` |
| RouteEvent | latitude ∈ [-90, 90]; longitude ∈ [-180, 180]; `description` obrigatória para `delay`/`incident` |
| RouteStop | `unique(route, sequence)`; ponto de encontro da mesma empresa da rota |
