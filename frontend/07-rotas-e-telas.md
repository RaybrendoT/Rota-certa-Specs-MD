# 07 — Rotas e telas

Fontes: `app.routes.ts`, `features/*/*.routes.ts`, componentes `*-list` e `*-detail`.

## 1. Mapa de navegação

Rotas públicas: `/login` (`guestGuard`) e `/alterar-senha` (`authenticatedGuard`). Todas as demais ficam sob `AppMenuComponent` (shell) com `managerGuard`.

| Caminho | Destino | Estado |
|---------|---------|--------|
| `/login` | `LoginComponent` | ok |
| `/alterar-senha` | `ChangePasswordComponent` | ok |
| `/` | redireciona para `/home` | ok |
| `/home` | `HomeComponent` | ok |
| `/dashboard` | `ReportMaintenanceComponent` ("Dashboard em manutenção") | placeholder |
| `/mapa` | `ReportMaintenanceComponent` ("Mapa ao vivo em manutenção") | placeholder |
| `/configuracoes` | `ReportMaintenanceComponent` | placeholder |
| `/relatorios` | `REPORT_ROUTES` → `ReportMaintenanceComponent` | placeholder |
| `/company` | `COMPANY_ROUTES` | ok |
| `/empresas` | redireciona para `/company` | ok |
| `/funcionarios` | `EMPLOYEE_ROUTES` | ok |
| `/veiculos` | `VEHICLE_ROUTES` | ok |
| `/rotas` | `ROUTE_ROUTES` | ok |
| `/horarios` | `SCHEDULE_ROUTES` | ok |
| `/eventos-rota` | `ROUTE_EVENT_ROUTES` | ok |

Cada domínio implementado expõe o mesmo trio de rotas filhas:

| Sub-rota | Componente |
|----------|-----------|
| `''` | `*-list` (listagem) |
| `novo` | `*-detail` (criação) |
| `:id/editar` | `*-detail` (edição) |

Não há rota curinga (`**`) nem página 404.

## 2. Menu

- **Barra superior**: Dashboard, Veículos, Rotas, Funcionários, Relatórios.
- **Menu lateral** — PRINCIPAL: Dashboard, Mapa ao vivo; GESTÃO: Empresas (`/company`), Funcionários, Veículos, Rotas, Horários, Eventos de Rota, Relatórios; CONFIG: Configurações.

## 3. Telas de listagem

Todas usam `MatTable` + `MatPaginator` com paginação **server-side** (`GET ?page=N&page_size=M`, opções 5/10/25/50, padrão 10). Nas listas de Funcionários, Rotas e Eventos de rota a troca de página passa por `debounceTime(250)`. Empresas exibe `isLoading` e `errorMessage` (“Não foi possível carregar as empresas.”).

| Tela | Colunas | Dados auxiliares carregados |
|------|---------|-----------------------------|
| Empresas | `name`, `is_active`, ações | — |
| Funcionários (pessoas) | `name`, empresa, `phone`, tipo (Funcionário/Motorista), acesso (`role`: Funcionário/Gestor/Motorista), código (matrícula ou CNH), `is_active`, ações | `companies/` (mapa id → nome) |
| Veículos | `plate_number`, `model`, `driver`, `capacity`, `is_active`, ações | — |
| Rotas | `name`, empresa, veículo, `is_active`, ações | `companies/`, `vehicles/` |
| Horários | empresa, `weekdays` (lista separada por vírgula), `time`, `is_active`, ações | `companies/` |
| Eventos de rota | rota, `event_type`, `description`, `timestamp`, ações | `routes/` |

Ação de excluir em todas: `confirm('Tem certeza…')` → `DELETE` → recarrega a lista.

## 4. Formulários

### Empresa (`company-detail`)
`name` (obrigatório) e `is_active` (checkbox). O formulário **não** expõe `email_domain` (campo existente na API/modelo).

### Funcionário / Motorista (`employee-detail`)
| Campo | Regra |
|-------|-------|
| `company` | Obrigatório; autocomplete por **nome**, convertido para `id` no envio. Se o nome não existir na lista: `alert('Selecione uma empresa válida da lista.')` |
| `name`, `phone` | Obrigatórios |
| `type` | `EMPLOYEE` (padrão) ou `DRIVER` |
| `employee_code` | Obrigatório se `EMPLOYEE`; zerado se `DRIVER` |
| `license_number` | Obrigatório se `DRIVER`; zerado se `EMPLOYEE` |
| `is_active` | Checkbox (padrão `true`) |
| `access_role` | Só na **edição** de `EMPLOYEE` com conta: Funcionário ou Gestor. Não vai no `PATCH people/`; se mudou, chama `POST people/{id}/access-role/` em seguida. Erros (ex.: remover o próprio perfil de gestor) aparecem em `alert` |

Troca de `type` reajusta validadores e limpa o campo do tipo oposto. Envio: `POST people/` ou `PATCH people/{id}/` (payload inclui `type`, `company` como id e o campo do outro tipo como `null`).

### Veículo (`vehicle-detail`)
`company` (select, obrigatório), `driver` (select, obrigatório; motoristas filtrados por `type === 'DRIVER'` a partir de `GET people/`), `plate_number`, `model` (obrigatórios), `capacity` (número, obrigatório), `is_active`.

### Rota (`route-detail`)
`name` (obrigatório), `company` (select, obrigatório), `vehicle` (select, obrigatório; rótulo `placa - modelo`), `is_active`.

### Horário (`schedule-detail`)
`company` (obrigatório), `weekdays` (texto, padrão `MON,TUE,WED,THU,FRI`, convertido para lista ao enviar), `time` (obrigatório), `is_active`.

### Evento de rota (`route-event-detail`)
`route` (select, obrigatório), `event_type` (padrão `departure`), `description` (**obrigatória no formulário**), `latitude`, `longitude` (obrigatórios), `is_active`.

## 5. Comportamentos comuns

- Sucesso ao salvar ⇒ navega para a lista do domínio.
- Erros de API são registrados em `console.error`; ao usuário só chegam a mensagem de erro da lista de Empresas e o `alert` de empresa inválida no formulário de pessoa.
- Nos formulários, `save()` retorna sem ação se o formulário for inválido (o botão Salvar/Atualizar de Empresa é desabilitado com `form.invalid`).
- Não há snackbar de sucesso/erro; o indicador de carregamento existe apenas na lista de Empresas.

## 6. Funcionalidades da API sem tela

Endereços, pontos de encontro, paradas de rota, passageiros de rota, autenticação/troca/redefinição de senha e visão do motorista não possuem telas no frontend web.
