# 08 — Integração frontend ↔ API

Contrato efetivamente usado pelo frontend por recurso, e pontos em que o frontend e o backend **não estão alinhados**. Referências cruzadas: `backend/03-api-rest.md` e `10-lacunas-e-melhorias.md`.

## 1. Contratos por recurso

| Tela | Serviço | Chamadas | Payload enviado |
|------|---------|----------|-----------------|
| Empresas | `CompanyService` | `GET companies/?page&page_size`, `GET companies/{id}/`, `POST`, `PATCH`, `DELETE` | `{ name, is_active }` |
| Funcionários / Motoristas | `EmployeeService` | `GET people/?page&page_size`, `GET people/{id}/`, `POST`, `PATCH`, `DELETE`, `POST people/{id}/access-role/` | `{ company:id, name, phone, type, license_number\|null, employee_code\|null, is_active }` |
| Veículos | `VehicleService` | `GET vehicles/…`, `POST`, `PATCH`, `DELETE` | `{ company, driver, plate_number, model, capacity, is_active }` |
| Rotas | `RouteService` | `GET routes/…`, `POST`, `PATCH`, `DELETE` | `{ name, company, vehicle, is_active }` |
| Horários | `ScheduleService` | `GET schedules/…`, `POST`, `PATCH`, `DELETE` | `{ company, weekdays:string[], time, is_active }` |
| Eventos de rota | `RouteEventService` | `GET route-events/…`, `POST`, `PATCH`, `DELETE` | `{ route, event_type, description, latitude, longitude, is_active }` |

Dados auxiliares: `companies/`, `vehicles/`, `routes/` e `people/` são consultados sem parâmetros para preencher selects e mapas id → nome.

## 2. Tratamento de respostas

O frontend aceita três formatos de lista (array simples, `{ results }` do DRF e `{ value }`), via `extractPaginatedItems/Count`. O backend sempre responde no formato DRF (`count/next/previous/results`) nos endpoints de lista.

## 3. Incompatibilidades e comportamentos divergentes

| ID | Situação | Efeito |
|----|----------|--------|
| I-01 | **Veículo**: o frontend envia `driver` (id). No backend `VehicleSerializer` declara `driver` como **somente leitura** (objeto `Person` aninhado) e espera `driver_id` na escrita | O motorista **não é gravado** ao criar/editar veículo pela web; o campo aceito é ignorado silenciosamente. Corrigir enviando `driver_id` (ou ajustando o serializer) |
| I-02 | **`page_size`**: o frontend envia `page_size` (5/10/25/50) | O backend não define `page_size_query_param`; o tamanho fica fixo em 10 e o paginador mostra opções que não têm efeito |
| I-03 | **Dados auxiliares paginados**: selects de empresa, veículo, rota e motorista usam `getAll()` sem `page` | Só os 10 primeiros registros aparecem nos selects/mapas; empresas, veículos, rotas ou motoristas além do 10º não podem ser escolhidos (e nomes ficam `-` nas listas) |
| I-04 | **Motoristas no formulário de veículo**: vêm de `people/` (1ª página) filtrados por `type=DRIVER` no cliente | Pode não listar motoristas existentes. Existe `GET drivers/` (ou `people/?type=DRIVER`) que resolveria no servidor |
| I-05 | **Rota sem veículo**: o formulário exige `vehicle`; a API permite `null` | Impossível criar rota sem veículo pela web |
| I-06 | **Evento de rota**: o formulário exige `description` para todos os tipos; a API só exige para `delay` e `incident`. `event_type` não é restrito a opções no cliente (modelo aceita `string`) | Regra mais rígida no frontend; tipos `arrival`/`incident` dependem de o usuário digitar o valor correto |
| I-07 | ~~**Autenticação**: o frontend não faz login nem envia `Authorization`~~ **Resolvido**: login, `authInterceptor` (com renovação em 401), guards e troca de senha; a API agora exige `MANAGER` para o CRUD | O painel só funciona com conta de perfil gestor |
| I-08 | ~~**Throttling** `anon`~~ Com token as chamadas contam como `user` (1000/h por conta) | Reduzido; o login e o reset continuam no `anon` por IP |
| I-09 | **Empresa**: o formulário não expõe `email_domain` | O domínio dos e-mails de acesso é sempre derivado do nome da empresa pela web |
| I-10 | **Horário**: `weekdays` é digitado como texto livre (`MON,TUE,…`) e convertido para lista | Sem validação de valores; a API aceita qualquer JSON |
| I-11 | **Base URL fixa**: `assets/config/config.json` traz um IP de LAN | Cada ambiente exige editar o arquivo; se a leitura falhar, `apiBaseUrl` vira `''` e as chamadas vão para a própria origem |
| I-12 | **Exclusão**: `DELETE` é físico e em cascata (ex.: excluir empresa apaga pessoas, rotas, veículos) | O frontend mostra apenas `confirm()` genérico, sem aviso de cascata |
| I-13 | **Funcionários × Motoristas**: a tela "Funcionários" usa `people/` e lista os dois tipos | Motoristas são cadastrados na mesma tela, escolhendo `type=DRIVER` |
| I-14 | **Erros de validação** (400 do DRF) não são exibidos ao usuário | Apenas `console.error`; erros como placa duplicada ou regras de `Person` passam despercebidos |

## 4. Recursos da API não consumidos pelo frontend

`people/` por tipo (`drivers/`, `employees/`), `addresses/`, `meeting-points/`, `route-stops/`, `route-passengers/`, `routes/my-routes|driver-detail|events|navigation`, e os endpoints `auth/*` além de `login`, `refresh`, `me` e `change-password` (o fluxo de recuperação de senha por OTP não tem tela).
