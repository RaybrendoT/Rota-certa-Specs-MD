# 00 — Visão geral

## 1. Objetivo

O **Rota Certa** permite que empresas gerenciem o transporte corporativo de seus funcionários: cadastro de empresas, motoristas, funcionários (passageiros), veículos, pontos de encontro, rotas com paradas ordenadas, horários de operação e registro de eventos ocorridos durante a execução das rotas.

## 2. Atores

| Ator | Descrição | Canal |
|------|-----------|-------|
| Gestor / RH | Administra cadastros e acompanha rotas | Frontend web Angular |
| Motorista (`DRIVER`) | Executa a rota, consulta paradas e passageiros, obtém navegação | App Android (consome a API) |
| Funcionário (`EMPLOYEE`) | Passageiro; possui conta de acesso, é vinculado a rotas | Cadastro via web; conta criada automaticamente |

## 3. Escopo funcional implementado

### Backend (Django REST Framework)

- **RF-01** CRUD de empresas, com domínio de e-mail configurável.
- **RF-02** CRUD de pessoas (motoristas e funcionários) em modelo único (`Person`), com endpoints agregados e especializados (`/people/`, `/drivers/`, `/employees/`).
- **RF-03** CRUD de veículos, com motorista opcional.
- **RF-04** CRUD de rotas, paradas de rota (`route-stops`), pontos de encontro (`meeting-points`), endereços (`addresses`), horários (`schedules`), passageiros de rota (`route-passengers`) e eventos de rota (`route-events`).
- **RF-05** Criação automática de conta de acesso (`AccessAccount`) ao cadastrar uma pessoa, com e-mail derivado e senha inicial.
- **RF-06** Autenticação JWT própria (login, refresh, verify, troca de senha, redefinição de senha por código).
- **RF-07** Visão do motorista: rotas atribuídas (`my-routes`), detalhe (`driver-detail`) e navegação com polyline via Google Routes API (`navigation`).

### Frontend (Angular 19)

- **RF-08** Telas de listagem e formulário (criar/editar/excluir) para: Empresas, Funcionários/Motoristas, Veículos, Rotas, Horários e Eventos de Rota.
- **RF-09** Layout com barra superior e menu lateral; página inicial (`home`).
- **RF-10** Páginas "em manutenção" para Dashboard, Mapa ao vivo, Relatórios e Configurações (funcionalidades ainda não implementadas).

## 4. Fora de escopo (estado atual)

- Login e controle de acesso no frontend web (não há tela de login, guard nem envio do token).
- Dashboard, mapa ao vivo, relatórios e configurações.
- Telas web para endereços, pontos de encontro, paradas de rota e passageiros de rota (existem apenas na API).
- Envio de e-mail/SMS do código de redefinição de senha.
- Rastreamento em tempo real.

## 5. Glossário

| Termo | Significado |
|-------|-------------|
| Person | Pessoa cadastrada; `type` = `DRIVER` ou `EMPLOYEE` |
| AccessAccount | Credencial de login vinculada 1:1 a uma `Person` |
| Route | Rota de transporte de uma empresa, opcionalmente com veículo |
| RouteStop | Parada ordenada (`sequence`) de uma rota, apontando para um `MeetingPoint` |
| MeetingPoint | Ponto de encontro nomeado com endereço geolocalizado |
| RoutePassenger | Vínculo funcionário ↔ rota (opcionalmente a uma parada) com status de embarque |
| RouteEvent | Ocorrência da rota: `departure`, `arrival`, `stop`, `delay`, `incident` |
| Schedule | Horário de operação (dias da semana + hora) de uma empresa |
