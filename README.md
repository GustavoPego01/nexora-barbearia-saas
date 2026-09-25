# Barbearia SaaS

Aplicação multiempresa em React, TypeScript e Supabase real, projeto **Barbearias**.
Login, papéis, onboarding, marca/temas, serviços, equipe, horários/bloqueios, agenda pública,
clientes/histórico, financeiro/comissões, Super Admin auditado e PWA estão implementados.
WhatsApp oficial tem Embedded Signup, webhook, bot e filas; ativação depende da Meta.

## Executar

Node.js 22.12+ (ambiente validado com Node 24). No PowerShell, use `npm.cmd` caso
a política de execução bloqueie `npm.ps1`.

```sh
npm ci
npm run dev
```

Abra `http://127.0.0.1:5173` após configurar o ambiente abaixo.

## Supabase

Copie `.env.example` para `.env.local` e preencha a URL do projeto e a chave pública
`sb_publishable_...`. Nunca use chave secreta/service_role em variáveis `VITE_*`.
Reinicie Vite após alterar o ambiente. Ter variáveis válidas não verifica a conexão.

Vincule seu projeto pela CLI antes de aplicar as migrations:

```sh
npx supabase link --project-ref SEU_PROJECT_REF
npx supabase db push --dry-run
npx supabase db push
```

## Verificação e build

```sh
npm run lint
npm run typecheck
npm run db:test
npm run test:real
npm run test:browser
npm run build
npm run preview
```

O build faz checagem TypeScript e gera `dist/`. O lint falha em warnings.
`test:real` usa a demo e deixa a reserva concorrente de teste cancelada para preservar auditoria.
`test:browser` requer o servidor local iniciado e Microsoft Edge instalado.
`npm run db:types` verifica o banco e regenera os tipos usados pelo cliente Supabase.
Instruções, permissões e limites dos testes: [Banco de dados](supabase/README.md).

## Publicação futura

Publicar `dist/` em hospedagem estática com HTTPS, variáveis públicas configuradas no
build e fallback das rotas SPA para `/index.html`. Configurar URLs de redirecionamento
no Supabase Auth. Backend e Edge Function já estão no Supabase; o frontend ainda roda localmente.
A PWA ativa service worker no build de produção. Para validar: `npm run preview -- --port 4173`,
depois `node scripts/pwa-smoke.mjs`. O cache contém somente shell/assets, nunca respostas privadas.

WhatsApp: [configuração externa da Meta](supabase/functions/README.md). SMTP próprio e domínio
HTTPS de produção ainda precisam ser definidos antes da comercialização. Confirmação de e-mail
permanece habilitada no Supabase. Não coloque segredos ou credenciais demo no Git.

O build verifica que `dist/` contém apenas arquivos do site, sem documentos internos,
credenciais ou source maps. Publique somente esse diretório.
