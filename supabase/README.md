# Banco multitenant — Etapa 2

## Arquivos e aplicação

Aplicar as migrations em ordem, como `postgres`, preferencialmente em **projeto Supabase
de desenvolvimento novo**. Não executar `tests/bootstrap.sql` no Supabase: ele simula
somente contratos Auth/Storage usados pelos testes locais. Cada migration é transacional.

1. `202609120001_core.sql`: entidades, enums, FKs compostas, índices e constraints.
2. `202609120002_security.sql`: RLS, privilégios de coluna, funções privadas e triggers.
3. `202609120003_storage.sql`: quatro buckets privados e políticas por empresa.

Com a [CLI oficial](https://supabase.com/docs/guides/local-development/cli/getting-started)
instalada e projeto criado:

```sh
supabase login
supabase link --project-ref SEU_PROJECT_REF
supabase db push --dry-run
supabase db push
```

Faça login no seu computador; nunca cole token de acesso, senha do banco ou service role
na conversa. O `project-ref` pode ser compartilhado. URL e chave pública `sb_publishable_...`
vão em `.env.local`. Elas conectam o frontend, mas **não autorizam migrations**.

No projeto remoto, exponha somente os schemas habituais da API (`public`,
`graphql_public`); **não exponha `private`**. A CLI local já possui isso em `config.toml`.
Projetos com políticas Storage preexistentes exigem revisão: a migration falha de propósito
para não somar permissões antigas às novas. Não apaga políticas ou dados existentes.

## Validação local sem conta

```sh
npm run db:test
npm run db:types
```

PGlite executa PostgreSQL real em WASM, incluindo RLS, GRANT, triggers, FKs e btree_gist.
O teste usa banco descartável em memória, dois tenants e usuários para todas as funções.
O gerador lê o catálogo das migrations executadas e produz `src/types/database.ts`.
Não instala dependência no bundle do navegador. As chaves não são necessárias.

**Limites:** os contratos de `auth.users`, `auth.uid()` e `storage` são simulados; não
validam JWT real, PostgREST, upload HTTP nem concorrência entre conexões independentes.
Esses testes permanecem necessários em Supabase antes de liberar uso comercial.
O teste sequencial de sobreposição confirma a constraint de exclusão e os bloqueios,
mas não equivale a um teste de carga/concorrência.

Com Docker e CLI disponíveis, `supabase start` inicia a stack real local. Use
`supabase db reset --local` **somente no banco local descartável**, pois apaga os dados
locais e reaplica migrations/seed. Não execute reset remoto.

## Segurança e escopo

- `auth.users` identifica pessoas. `profiles` contém só perfil; função vem de membership.
- Tabelas de empresa usam `barbershop_id NOT NULL`, índices e FKs compostas; tenant e ID
  de registros não mudam. Cadastros globais `plans`/`themes` são leitura pública.
- Sessões sem membership válida não acessam a empresa. Conta inativa, trial expirado,
  assinatura expirada/bloqueada/past_due/cancelled negam acesso operacional.
- Proprietário/gerente/recepção têm CRUD limitado aos módulos autorizados; profissional
  acessa sua agenda e clientes atendidos. Cliente lê seus dados e horários, sem notas internas.
- `appointments` usa privilégios de coluna: **não consultar `select('*')`** nesta etapa.
  Selecione explicitamente campos públicos da agenda; `commission_percent` é privado.
- O cadastro completo do profissional só é visível a ele com comissões habilitadas.
  Projeções próprias sem dados financeiros serão adicionadas com os fluxos da equipe.
- Membership, subscriptions, plans e conexões WhatsApp não aceitam escrita do navegador.
  Identidade `customers.user_id` também não é vinculável por CRUD genérico.
- Agenda, pagamentos, bloqueios e filas ficam somente leitura no navegador até as RPCs
  transacionais das etapas correspondentes. Não há atalho de reserva direta.
- Exclusão GiST impede sobreposição por profissional e inclui buffer. Triggers serializam
  bloqueios/reservas pela empresa. Limites de profissionais serializam pela assinatura.
- Receita tem unicidade por atendimento; conclusão, snapshots e estorno serão implementados
  na Etapa 13. Regras completas de disponibilidade e cancelamento virão na Etapa 10.
- Auditoria registra ator, empresa, ação, entidade e horário sem copiar payloads privados.
  Logs não podem ser editados pelo cliente. Tabela de super admins é privada e não concede
  bypass automático; suporte registra a sessão, mas seu fluxo de autorização virá na Etapa 15.
- Buckets `logos`, `covers`, `professionals`, `service-images`: privados, imagens JPEG/PNG/WebP,
  prefixo `barbershop_id/arquivo`, limites de tamanho. Owner gerencia todos; manager apenas
  fotos de profissionais/serviços. Página pública/projeções seguras virão na Etapa 12.
- Tokens Meta ficam fora dessas tabelas, exclusivamente em secrets/backend futuro.

O seed contém a Barbearia Prime, três profissionais, quatro serviços e horários com almoço.
Não cria senha, usuário autenticável, super admin ou empresa publicada. É exclusivo para
ambiente de desenvolvimento e não é enviado por `supabase db push`.

Referências: [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security),
[funções](https://supabase.com/docs/guides/database/functions),
[Storage](https://supabase.com/docs/guides/storage/security/access-control).
