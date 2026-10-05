# Rota Certa 2026 — Specs

Especificações do projeto **Rota Certa** (gestão de rotas de transporte corporativo), derivadas do código-fonte atual do **Backend Django** e do **Frontend Angular**. Descrevem o sistema **como ele está implementado hoje**; divergências e melhorias ficam isoladas em `10-lacunas-e-melhorias.md`.

> Escopo: backend (`Rota-certa-2026 (Backend Django)`) e frontend web (`Rota-certa-2026 (Frontend Angular)`). O app Android (Kotlin) não faz parte destas specs, mas consome a mesma API (ver `backend/03-api-rest.md`, seção "Endpoints do app do motorista").

## Índice

| # | Documento | Conteúdo |
|---|-----------|----------|
| 00 | [Visão geral](00-visao-geral.md) | Objetivo, atores, escopo, glossário |
| 01 | [Arquitetura](01-arquitetura.md) | Componentes, stack, fluxo entre camadas |
| 02 | [Modelo de dados](backend/02-modelo-de-dados.md) | Entidades, campos, relacionamentos, constraints |
| 03 | [API REST](backend/03-api-rest.md) | Endpoints, filtros, payloads, paginação |
| 04 | [Autenticação e segurança](backend/04-autenticacao-e-seguranca.md) | JWT, contas de acesso, reset de senha, bloqueio |
| 05 | [Regras de negócio](backend/05-regras-de-negocio.md) | Validações, signals, cálculo de rota |
| 06 | [Arquitetura do frontend](frontend/06-arquitetura-frontend.md) | Estrutura, serviços, config, interceptors |
| 07 | [Rotas e telas](frontend/07-rotas-e-telas.md) | Mapa de navegação, telas, formulários |
| 08 | [Integração frontend ↔ API](frontend/08-integracao-api.md) | Contratos por recurso e incompatibilidades |
| 09 | [Configuração e execução](09-configuracao-e-execucao.md) | Variáveis de ambiente, setup, deploy |
| 10 | [Lacunas e melhorias](10-lacunas-e-melhorias.md) | Divergências, riscos e backlog sugerido |
| 11 | [Code review do backend](11-code-review-backend.md) | Conflitos de autenticação, redundâncias e checklist para o app Kotlin |
| DB-1 | [Mapa do banco](database/01-mapa-do-banco.md) | Tabelas, colunas, relacionamentos, integridade, índices |
| DB-2 | [Plano de subida na AWS](database/02-plano-de-subida-aws.md) | Decisões, fases, riscos e insumos para os YAML |
| DB-3 | [Migrações e superusuário](database/03-migrations-e-superuser.md) | Migração 0006, alternativas, endurecimento e testes |
| DB-4 | [PostgreSQL exclusivo](database/04-postgres-exclusivo.md) | Fim do fallback para SQLite: achado, risco, código proposto e testes |
| DB-5 | [Plano de backup](database/05-plano-de-backup.md) | Backup por imagem × backup tradicional, recomendação, runbook de restauração |
| — | [`database/migrations/`](database/migrations/0007_create_initial_superuser.py) · [`database/sql/`](database/sql/01_roles_e_banco.sql) | Migração do superusuário (0007 — já aplicada ao repositório); SQL de papéis e de verificação |

## Convenções

- Prefixo da API: `/api/`. Todos os caminhos de endpoint nas specs são relativos a ele.
- Identificadores são inteiros (`BigAutoField`), não UUID.
- Nomes de campos em `snake_case` (JSON e banco).
- "RF" = requisito funcional, "RN" = regra de negócio, "RNF" = requisito não funcional.
