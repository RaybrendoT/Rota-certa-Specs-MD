-- Rota Certa — criação do banco e dos papéis (PostgreSQL 14+).
--
-- Executar UMA vez, como administrador do servidor:
--   * RDS: o "master user" (não é SUPERUSER de verdade; é membro de rds_superuser)
--   * PostgreSQL no cluster: o usuário `postgres` (SUPERUSER do servidor)
--
-- Uso (senhas vêm de variáveis, nunca escritas no arquivo):
--   psql "host=<host> dbname=postgres user=<admin> sslmode=require" \
--        -v owner_pw="$ROTACERTA_OWNER_PASSWORD" -v app_pw="$ROTACERTA_APP_PASSWORD" \
--        -f 01_roles_e_banco.sql
--
-- Papéis:
--   rotacerta_owner : dono do banco/objetos. Usado SÓ pelo Job de migrate (DDL).
--   rotacerta_app   : usado pelo Deployment do backend. Apenas DML (sem CREATE/ALTER/DROP).
--   (SUPERUSER do servidor NÃO é usado pela aplicação.)

\set ON_ERROR_STOP on

-- 1) Papéis (sem SUPERUSER, sem CREATEDB, sem CREATEROLE)
CREATE ROLE rotacerta_owner LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD :'owner_pw';
CREATE ROLE rotacerta_app   LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD :'app_pw';

-- 2) Somente no RDS: o admin precisa ser membro do papel para criar um banco cujo dono é ele.
--    (Em PostgreSQL comum, um SUPERUSER dispensa esta linha; ela também é inofensiva lá.)
GRANT rotacerta_owner TO CURRENT_USER;

-- 3) Banco
CREATE DATABASE rotacerta
    OWNER rotacerta_owner
    ENCODING 'UTF8'
    TEMPLATE template0;

REVOKE ALL ON DATABASE rotacerta FROM PUBLIC;
GRANT CONNECT ON DATABASE rotacerta TO rotacerta_app;

\connect rotacerta

-- 4) Schema public: ninguém além do dono cria objetos
--    (RDS/PostgreSQL 15+: o schema public pertence ao dono do banco. Se o REVOKE/GRANT abaixo
--     for recusado para o admin, reconecte como rotacerta_owner e execute os passos 4 e 5 por lá.)
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE, CREATE ON SCHEMA public TO rotacerta_owner;
GRANT USAGE ON SCHEMA public TO rotacerta_app;

-- 5) Tudo que o owner criar (tabelas do migrate) já nasce acessível ao app, só com DML
ALTER DEFAULT PRIVILEGES FOR ROLE rotacerta_owner IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO rotacerta_app;
ALTER DEFAULT PRIVILEGES FOR ROLE rotacerta_owner IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO rotacerta_app;

-- 6) Limite de conexões por papel (instância pequena)
ALTER ROLE rotacerta_app   CONNECTION LIMIT 20;
ALTER ROLE rotacerta_owner CONNECTION LIMIT 5;

-- 7) Fuso de sessão (o Django trabalha em UTC)
ALTER DATABASE rotacerta SET timezone TO 'UTC';
