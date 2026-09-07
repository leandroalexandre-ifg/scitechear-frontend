# Integração com o backend — correspondência

Os documentos trocados entre este repositório e o `scitechear-backend` em
07/09/2026, na ordem em que aconteceram. Estão aqui porque **o contrato entre
os dois lados foi decidido nesta conversa**, e a maior parte do "por quê" de
`api_client.dart`, `status_service.dart` e `participant_service.dart` está
nestes arquivos, não no código.

Não são documentação de referência — para isso, use
[`../ARCHITECTURE.md`](../ARCHITECTURE.md) (o sistema) e
[`../FRONTEND_ARCHITECTURE.md`](../FRONTEND_ARCHITECTURE.md) (este app), que
são mantidos atualizados. Estes são registro histórico: descrevem o que era
verdade quando foram escritos, e alguns pontos foram superados por rodadas
seguintes.

| # | Documento | O que foi decidido |
|---|---|---|
| 1 | [Relatório do frontend](01-relatorio-do-frontend.md) | O app não funcionava mais contra o backend: todas as rotas passaram a exigir `Bearer` e o `auth_service` era um mock. Levanta três premissas de sessão para confirmação. |
| 2 | [Resposta do frontend](02-resposta-do-frontend.md) | 403 no cadastro tratado no campo do e-mail; 413; `Retry-After` como limite superior; sete códigos de erro traduzidos; `isAdmin` removido. |
| 3 | [`participant_id`](03-participant-ids.md) | Os ids **não** são estáveis: reinstalar órfãva todos os perfis de voz. A fila de exclusões pendentes nasce aqui. |
| 4 | [`GET /participants`](04-get-participants.md) | A rota de listagem resolve a reinstalação: o cadastro é semeado de volta em vez de recriado com ids novos. |
| 5 | [Smoke do contrato](05-smoke-contrato.md) | `DELETE .../voice-profile` é 204 sempre; o `4401` do WebSocket nunca chegava a cliente nenhum. |
| 6 | [Diagramas desatualizados](06-diagramas-desatualizados.md) | Quatro dos cinco SVG tinham ficado para trás — o pior deles mostrava o processamento como thread da API, e não como worker dedicado. Pede espelhamento. |

## Três coisas que estes documentos estabeleceram, e que continuam valendo

**O refresh token é rotacionado no uso, sem janela de graça.** Por isso o
`ApiClient` serializa renovações concorrentes: sem isso, N chamadas paralelas
com o token vencido fariam N−1 falharem. Não há detecção de reuso em cascata
hoje — se o backend adicionar, isto vira crítico, e eles avisam antes.

**O `user_id` é imutável e não há endpoint de exclusão de conta.** É o que
autoriza usá-lo como chave de escopo do armazenamento local.

**Quem classifica um erro é a resposta HTTP, não o código de fechamento do
WebSocket.** O app cai no polling em qualquer fechamento não-terminal e deixa
a resposta HTTP seguinte decidir. Vale a pena conhecer o custo: o app não
distingue "não abri o WS" de "abri e fui recusado" — foi por isso que o bug
do `4401` (documento 5) passou por três rodadas de relatório sem ninguém
notar.
