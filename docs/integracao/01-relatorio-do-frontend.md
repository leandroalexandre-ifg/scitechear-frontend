# Relatório do frontend para o backend — SciTech Ear

**Data:** 07/09/2026
**Repositório:** SciTech-frontend, branch `main`, commit `82af9b4`
**Contexto:** o app estava desenvolvendo contra um contrato antigo e um login
mock. Esta rodada alinhou o cliente ao backend que existe hoje. Nada disso
foi exercitado contra o servidor rodando — ver "O que ainda não foi
verificado" e "Teste conjunto proposto" no fim.

---

## 1. O que mudou no app

Cinco entregas, nesta ordem:

1. **Correção de um bug de gravação** (truncamento silencioso de reuniões
   longas). Detalhe no §6 — importa para o backend só por um motivo, que
   está lá.
2. **Suíte de testes destravada** (estava com um teste quebrado e uma
   asserção vazia). Hoje: 16 testes, `flutter analyze` limpo.
3. **README sincronizado** com o backend real.
4. **Autenticação real integrada** (`/auth/*`, JWT + refresh).
5. **Dados locais escopados por usuário**, consequência direta da 4.

O achado que motivou tudo: **o app não funcionava mais contra o backend.**
Desde 03/09 todas as rotas consumidas exigem `Bearer`, e o `auth_service`
do app era um mock local que nunca emitia token. Toda chamada voltaria 401
e o WebSocket fecharia com 4401. Isso não aparecia porque o
desenvolvimento recente rodava em modo demo.

---

## 2. O contrato que o app assume hoje

Se algum destes pontos mudar, o app quebra. Listado para servir de
checklist antes de qualquer alteração de API.

### Autenticação

| Rota | O que o app envia | O que espera |
|---|---|---|
| `POST /auth/register` | `{email, password, name}` | 201 + `UserPublic`. **Não espera tokens** — faz `login` logo em seguida |
| `POST /auth/login` | `{email, password}` | `{access_token, refresh_token, token_type, expires_in}` |
| `POST /auth/refresh` | `{refresh_token}` | mesmo `TokenPair` |
| `POST /auth/logout` | `{refresh_token}` | 204 |
| `GET /auth/me` | `Bearer` | `{user_id, email, name?}` |

- Senha: o app valida **mínimo 8** no cadastro, espelhando o
  `Field(min_length=8)`. No login não valida tamanho.
- E-mail: campo único de identificação, porque o backend tipa `EmailStr`.
  O app **não** suporta mais login por nome de usuário.
- Erros lidos de **`detail`** (não `message`). Tratados: 401 (credencial),
  409 (e-mail duplicado), 429 (usa o header `Retry-After` para dizer ao
  usuário quanto esperar), 422 (validação).

### Jobs e participantes

- `POST /upload` multipart: `file` (WAV 16 kHz mono), `title?`,
  `participants` (**campo JSON único** com `[{id, name}]`),
  `expected_speaker_count?` → 202 `{job_id, status}`.
- `GET /status/{job_id}` → `{job_id, status, progress?, error?{code,message}, updated_at}`.
- `GET /resultado/{job_id}` → 409 enquanto o status não for `done`.
- `WS /ws/{job_id}?token=<access_token>` — token na query string. O app
  trata 4401 e 4404 caindo para o polling.
- `POST /participants/{id}/voice-samples` (multipart `file`, `name`) e
  `DELETE /participants/{id}/voice-profile`.
- Estados consumidos: `queued`, `transcribing`, `diarizing`, `identifying`,
  `summarizing`, `extracting`, `done`, `error`.
- O `MeetingResult` do app espelha campo a campo o schema atual
  (`segments` com `id/cluster/participant_id/speaker/identified/confidence/
  start/end/text`, `questions` com `type` e `source_segment_ids`,
  `metadata`). Essa parte **já estava em dia** antes desta rodada.

---

## 3. Três premissas que o app adotou e que precisam de confirmação

Estas foram inferidas do código do backend, não documentadas em contrato.
São o principal motivo deste relatório.

**3.1. O refresh token é rotacionado/revogado no uso.**
Li em `auth_service.py` que `refresh()` invalida o token apresentado e
emite um par novo. Por causa disso, o app **serializa renovações
concorrentes**: se várias chamadas pegarem o token vencido ao mesmo tempo,
todas compartilham um único `POST /auth/refresh`. Sem isso, N chamadas
paralelas fariam N−1 falharem e o usuário seria deslogado por estar usando
o app em duas telas ao mesmo tempo.
👉 **Confirmar.** Se o refresh **não** for rotacionado, a serialização
continua correta (só deixa de ser obrigatória). Se for rotacionado *e* o
backend passar a aceitar reuso por uma janela de graça, avisar — muda a
severidade.

**3.2. `expires_in` é a validade do access token, em segundos.**
O app renova proativamente quando faltam menos de **2 minutos**, em vez de
esperar o 401. Isso evita, entre outras coisas, ter que reenviar um upload
multipart cujo corpo já foi consumido.
👉 **Confirmar** a unidade e que o valor se refere ao access token (hoje
30 min por `JWT_ACCESS_TOKEN_EXPIRE_MINUTES`).

**3.3. `user_id` é estável e imutável por conta.**
Esta é a mais importante. O app agora usa o `user_id` de `/auth/me` como
**chave de escopo do armazenamento local** (histórico de reuniões, cadastro
de participantes, cache de transcrições). Se o `user_id` de uma conta mudar
entre sessões, o usuário perde de vista todos os dados locais dele.
👉 **Confirmar** que é imutável. Se houver qualquer cenário em que mude
(migração de banco, recriação de conta com mesmo e-mail), precisamos saber
antes.

---

## 4. Perguntas abertas

1. **`/auth/logout` revoga só aquele refresh token ou todos da conta?** O
   app manda o token corrente e assume que revoga só ele. Se revogar todos,
   sair em um aparelho derrubaria os outros — comportamento defensável, mas
   queremos documentar.
2. **Limites de rate limiting de login/register.** O app já mostra "tente
   novamente em ~X minutos" a partir do `Retry-After`. Saber os valores
   ajuda a escrever a mensagem certa e a não esbarrar neles em teste.
3. **Códigos de `error.code` em `/status`.** Hoje o app mostra o
   `error.message` cru ao usuário. Se houver um conjunto fechado de códigos,
   o app pode traduzir para mensagens melhores em português.
4. **`GET /meetings`.** O backend expõe; o app ainda usa histórico local em
   `shared_preferences`. Há intenção de o app migrar para a fonte do
   servidor? Isso resolveria a divergência de vez e tornaria o histórico
   consistente entre aparelhos. **Não é bloqueante** — só queremos alinhar a
   direção antes de investir em um dos dois lados.
5. **Push de progresso no WebSocket (Fase 8).** O `/ws` é stub hoje: manda
   o status uma vez e fecha. O app trata isso corretamente (cai no polling
   quando o WS fecha sem status terminal). **Pedido:** avisar quando o push
   real entrar, e não presumir que o app pode largar o polling — a remoção
   precisa ser combinada, senão volta o bug de tela travada.
6. **Papel de administrador.** O `UserPublic` não tem noção de papel. O app
   tem um `AppUser.isAdmin` vestigial (sempre `false`) e um selo na tela
   inicial que nunca aparece. Há plano de haver papéis? Se não houver,
   removemos o resto do campo daqui.

---

## 5. Mudanças que afetam quem testa o backend

- **A conta `leandro`/`leandro` não existe mais no app.** Não era uma conta,
  era um ramo do login mock. É preciso cadastrar uma conta real via
  `/auth/register`.
- **Senha de no mínimo 8 caracteres** no cadastro pelo app.
- **Login só por e-mail.**
- Para demonstrar o fluxo sem servidor, o app continua com
  `--dart-define=SCITECH_DEMO_MODE=true`. Ele **nunca** cai em resultado
  fictício por falha de rede — se o backend não responde, aparece o erro
  real. Se em algum teste aparecer transcrição plausível sem o backend no
  ar, é a flag ligada, não fallback silencioso.

---

## 6. Uma coisa do lado do app que o backend deve saber

Corrigimos um bug em que o gravador do Android encerrava sozinho no meio da
reunião (`AudioRecord.ERROR_DEAD_OBJECT`, comum em Samsung sob otimização
de bateria), produzindo um WAV **válido porém truncado** — sem erro visível.
O app agora detecta e oferece ao usuário enviar o trecho recuperado.

**Consequência para o backend:** nenhuma mudança de contrato, mas passa a
ser esperado receber, de vez em quando, um áudio bem mais curto do que a
reunião real, enviado deliberadamente. Não é upload corrompido; deve ser
processado normalmente.

Também corrigimos algo que valia dos dois lados: o app lia a mensagem de
erro do servidor de `data['message']`, campo que o FastAPI não usa (é
`detail`). Na prática **nenhum erro do backend jamais chegou ao usuário** —
todos viravam um texto genérico com o código HTTP. Se em algum momento o
backend padronizar o corpo de erro em outro formato, precisamos ser
avisados.

---

## 7. O que ainda não foi verificado

Sendo explícito para não haver falsa confiança:

- **A autenticação nunca rodou contra o backend real.** Os 16 testes do app
  usam um adaptador HTTP falso. O que está provado é a lógica de sessão
  (renovação proativa, serialização de refresh concorrente, não deslogar em
  falha de rede, isolamento local por usuário) — não a conversa real.
- **A correção do truncamento nunca disparou em aparelho.** O comportamento
  foi confirmado lendo o Kotlin do `record_android`; falta ver acontecer.
- **O isolamento local entre contas** está coberto por teste, mas nunca foi
  exercido com duas contas reais no mesmo aparelho.

---

## 8. Teste conjunto proposto

Um roteiro só, que valida os três pontos acima de uma vez:

1. Subir a API **e o worker** (`python -m app.worker` — sem ele o job fica
   parado em `queued`; isso faltava no nosso README e já foi corrigido).
2. `adb reverse tcp:8000 tcp:8000`, app apontando para `127.0.0.1:8000`.
3. Cadastrar **duas** contas pelo app (A e B).
4. Com a conta A: cadastrar participante com amostra de voz, gravar uma
   reunião **longa** (>10 min, de preferência num Samsung) e enviar.
5. Acompanhar o processamento até `done` e abrir o resultado.
6. Sair, entrar com a conta B: o histórico e os participantes têm que
   aparecer **vazios**.
7. Voltar para a conta A: tudo tem que reaparecer.

O que cada passo prova: 4–5 validam autenticação, upload, WebSocket com
token e o pipeline ponta a ponta; 4 também é a chance de o truncamento
aparecer; 6–7 validam o isolamento por usuário.

Do lado do backend, o que ajudaria durante esse teste: log de 401 nas
rotas protegidas (para distinguir "token ausente" de "token inválido") e o
motivo do fechamento do WebSocket (4401 vs 4404).

---

## 9. Resumo do estado da integração

| Área | Situação |
|---|---|
| Autenticação, renovação, escopo por usuário | integrado no app, **não testado contra o servidor** |
| Rotas protegidas (`Bearer`) | integrado |
| WebSocket com `?token=` | integrado |
| Schema de resultado | em dia (já estava) |
| Upload (`participants` JSON) | em dia |
| Amostra de voz (endpoint dedicado) | em dia |
| Push de progresso no `/ws` | **pendente no backend** (Fase 8); app com polling |
| `GET /meetings` | exposto, **não consumido** pelo app — decisão pendente |
| Papéis/admin | não existe no backend; resíduo inerte no app |
