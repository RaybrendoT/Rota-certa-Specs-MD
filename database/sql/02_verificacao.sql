-- Rota Certa — verificação pós-migrate. Somente leitura.
--   psql "host=<host> dbname=rotacerta user=rotacerta_owner sslmode=require" -f 02_verificacao.sql
-- Esperado (ver database/01-mapa-do-banco.md): 21 tabelas, 17 FKs no domínio,
-- migrações core 0001..0007 e auth 0001..0012 aplicadas, 1 superusuário.

\echo '== 1. Tabelas (esperado: 21) =='
SELECT count(*) AS tabelas FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE';

SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE' ORDER BY 1;

\echo '== 2. Migrações do app core (esperado: 0001..0007) =='
SELECT name, applied FROM django_migrations WHERE app = 'core' ORDER BY id;

\echo '== 3. Última migração de auth (esperado: 0012_alter_user_first_name_max_length) =='
SELECT name FROM django_migrations WHERE app = 'auth' ORDER BY id DESC LIMIT 1;

\echo '== 4. Chaves estrangeiras do domínio (esperado: 17) =='
SELECT count(*) AS fks FROM information_schema.table_constraints
WHERE constraint_type = 'FOREIGN KEY' AND table_schema = 'public' AND table_name LIKE 'core\_%';

\echo '== 5. Índices e constraints únicas do domínio =='
SELECT tablename, indexname, indexdef FROM pg_indexes
WHERE schemaname = 'public' AND tablename LIKE 'core\_%' ORDER BY tablename, indexname;

\echo '== 6. Superusuário do Django admin (sem mostrar o hash) =='
SELECT id, username, email, is_staff, is_superuser, is_active, date_joined, last_login
FROM auth_user WHERE is_superuser ORDER BY id;

\echo '== 7. Privilégios: o papel da aplicação NÃO deve conseguir criar objetos =='
SELECT has_schema_privilege('rotacerta_app', 'public', 'CREATE') AS app_pode_criar_objetos,
       has_table_privilege('rotacerta_app', 'core_company', 'INSERT') AS app_pode_inserir;

\echo '== 8. Tamanho das tabelas =='
SELECT relname AS tabela, pg_size_pretty(pg_total_relation_size(oid)) AS tamanho
FROM pg_class WHERE relkind = 'r' AND relnamespace = 'public'::regnamespace
ORDER BY pg_total_relation_size(oid) DESC LIMIT 15;

\echo '== 9. Conexões atuais por papel =='
SELECT usename, count(*) FROM pg_stat_activity WHERE datname = 'rotacerta' GROUP BY usename;
