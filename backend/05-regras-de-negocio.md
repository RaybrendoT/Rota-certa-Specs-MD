# 05 — Regras de negócio

Cada regra indica onde é aplicada. Fontes: `models.py`, `serializers.py`, `viewsets.py`, `signals.py`.

## 1. Pessoas

- **RN-01** Tipo `DRIVER` exige `license_number` e proíbe `employee_code`; tipo `EMPLOYEE` exige `employee_code` e proíbe `license_number` (`Person.clean()`, chamado em `save()`).
- **RN-02** Os endpoints `drivers/` e `employees/` forçam o `type` correspondente e zeram o campo do outro tipo (`DriverSerializer`, `EmployeeSerializer`).
- **RN-03** Erros de validação do model são convertidos em `400` com `message_dict` pelo `PersonSerializer`.

## 2. Contas de acesso

- **RN-04** Toda pessoa ativa recebe uma `AccessAccount` automática quando possível (ver `04-autenticacao-e-seguranca.md`, seção 2).
- **RN-05** E-mail de acesso = `{matrícula|licença}@{domínio}`; domínio vem de `Company.email_domain` ou é derivado do nome da empresa.
- **RN-06** Mudança de `employee_code`/`license_number` da pessoa ou de `email_domain` da empresa sincroniza o e-mail das contas, salvo colisão.
- **RN-07** Primeiro acesso exige troca de senha (`must_change_password = True`).
- **RN-08** 5 falhas consecutivas de login bloqueiam a conta por 30 minutos.

## 3. Veículos

- **RN-09** Apenas pessoas `DRIVER` podem ser vinculadas a um veículo (`driver_id`).
- **RN-10** `plate_number` é único no sistema.
- **RN-11** Excluir o motorista mantém o veículo (`driver` → `NULL`).

## 4. Rotas, paradas e passageiros

- **RN-12** O motorista de uma rota é o motorista do veículo atribuído (`route.vehicle.driver`); o app do motorista lista apenas rotas nesse vínculo.
- **RN-13** Cada rota tem paradas com `sequence` única (começa em 0). O ponto de encontro da parada deve pertencer à mesma empresa da rota.
- **RN-14** Apenas `EMPLOYEE` pode ser passageiro; uma pessoa só pode aparecer uma vez por rota.
- **RN-15** A parada de embarque do passageiro, quando informada, deve pertencer à mesma rota.
- **RN-16** `boarding_status` ∈ {`pending`, `confirmed`, `absent`}; inicia `pending`.

## 5. Eventos de rota

- **RN-17** Tipos válidos: `departure`, `arrival`, `stop`, `delay`, `incident`.
- **RN-18** `description` é obrigatória para `delay` e `incident`.
- **RN-19** Coordenadas devem estar em faixa geográfica válida (lat ±90, lon ±180).
- **RN-20** O status exibido ao motorista (`route_status`) é derivado do evento mais recente (ver `03-api-rest.md`, seção 3).

## 6. Navegação (Google Routes API)

- **RN-21** Somente motoristas acessam `routes/{id}/navigation/` e apenas para rotas do seu veículo.
- **RN-22** **Origem**: primeiro endereço ativo vinculado à pessoa do motorista.
- **RN-23** **Destino**: primeiro endereço ativo da empresa da rota (sem pessoa) que **não** seja endereço de nenhuma parada da rota.
- **RN-24** **Intermediários**: endereços dos pontos de encontro das paradas, na ordem de `sequence`.
- **RN-25** Requisição ao Google: `travelMode=DRIVE`, `routingPreference=TRAFFIC_AWARE`, `languageCode=pt-BR`, `units=METRIC`, sem rotas alternativas; timeout de 15 s. Campos pedidos: duração, distância, polyline e instruções dos passos.
- **RN-26** Formatação: duração em minutos arredondados (mín. 1 min); distância em km com 1 casa se ≥ 1000 m, senão em metros. Sem instrução disponível, retorna "Siga a rota".

## 7. Ciclo de vida dos dados

- **RN-27** Listagem e detalhe pela API mostram apenas registros com `is_active=True`.
- **RN-28** `DELETE` remove fisicamente o registro e propaga por CASCADE conforme o modelo (ver `02-modelo-de-dados.md`).
- **RN-29** Para "desativar" um registro, use `PATCH { "is_active": false }`; ele deixa de aparecer, mas permanece no banco.
- **RN-30** Todos os serializers expõem `is_active` com `default=True`, portanto um `PUT`/`POST` sem o campo reativa/cria como ativo.

## 8. Dados de demonstração e manutenção (comandos)

| Comando | Opções | Finalidade |
|---------|--------|------------|
| `python manage.py seed_manaus_demo` | `--people N` (padrão e mínimo 50; ~1/5 motoristas, mín. 10) | Popula dados demo de Manaus em transação: empresas, horários, pontos de encontro, pessoas, veículos, rotas, paradas, passageiros e eventos, mais um **gestor demo** (`mng001@polodigitalmanaus.com`, senha inicial `MNG0010001`, troca obrigatória no 1º login) |
| `python manage.py ensure_access_accounts` | `--password <fixa>`, `--dry-run` | Cria `AccessAccount` para pessoas ativas sem conta (registros antigos ou com auto-criação desligada). Sem `--password`, usa a senha inicial padrão (matrícula/licença + 4 últimos dígitos do telefone) |
| `python manage.py set_access_role <email> <EMPLOYEE\|MANAGER>` | — | Define o perfil de acesso da conta (é como se cria o primeiro gestor). `DRIVER` não é atribuível; falha se violar a regra de consistência com o tipo da pessoa |
| `python manage.py reset_initial_access_passwords` | `--dry-run`, `--all` | Redefine para a senha inicial padrão as contas ativas com `must_change_password=True` (`--all` inclui as demais) |

> O texto de ajuda de `ensure_access_accounts --password` menciona "DDMMAAAA de created_at", mas o código usa a regra matrícula + telefone (ver `10-lacunas-e-melhorias.md`, D-05).
