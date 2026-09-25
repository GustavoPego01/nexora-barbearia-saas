# WhatsApp oficial

A Edge Function `whatsapp` já está publicada. Nenhuma biblioteca de WhatsApp Web é usada.
O proprietário usa **Conectar com a Meta**, com Embedded Signup. O servidor troca o código,
verifica o vínculo do número e criptografa o token por empresa. O navegador nunca recebe tokens Meta.

Pendente da conta da plataforma na Meta: App Review/permissões WhatsApp, Facebook Login for
Business, configuração de Embedded Signup e domínio HTTPS autorizado. Configure **apenas nos
secrets da Edge Function**: `META_APP_ID`, `META_APP_SECRET`, `META_LOGIN_CONFIG_ID`,
`META_GRAPH_VERSION` (versão suportada pelo seu app). Atualize `APP_ORIGINS` e `APP_PUBLIC_URL`
para o domínio público. Os segredos internos de criptografia, webhook e dispatcher já foram gerados.

Webhook: `https://rgvzmlfnjflqkzjoogyr.supabase.co/functions/v1/whatsapp?action=webhook`.
O verify token está em `.supabase-whatsapp.local` (ignorado pelo Git). Não publique esse arquivo.
A assinatura HMAC é validada antes de aceitar eventos; mensagens recebidas são deduplicadas.

Após habilitar a conta/número oficialmente, agende chamada por minuto a `?action=dispatch`,
com `Authorization: Bearer <WHATSAPP_CRON_SECRET>` via cron seguro. O agendamento não foi
ativado antes das credenciais para evitar execuções inúteis. Filas têm claim com lock e limite
de tentativas; envios externos têm semântica de ao menos uma vez em falhas ambíguas da Meta.

O bot determinístico oferece serviço → profissional → data → horário → nome → reserva
na mesma agenda, usando a mesma validação de disponibilidade e constraints. Na migration 014, também cancela e remarca com confirmação, prazo e validação do remetente; uma disputa de horário preserva a reserva anterior. As respostas e ativação do assistente são configuráveis por empresa. Também consulta
horários pelo remetente verificado e permite encaminhar a conversa à equipe. Respostas são
persistidas para que uma repetição do webhook não gere uma segunda reserva.
Lembretes/avisos usam templates aprovados: configure o nome e os parâmetros correspondentes
na tela. Rascunhos locais não representam aprovação da Meta. Envios e Embedded Signup só
poderão ser validados de ponta a ponta depois da liberação externa.

Atualização local 014: o registro oficial do número inclui PIN criptografado somente no schema privado; falhas de autorização têm estado de erro. Migration 014 aplicada e Edge Function atualizada no projeto existente. O registro e o envio reais ainda dependem da liberação da Meta.
