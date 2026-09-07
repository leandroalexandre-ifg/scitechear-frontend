# Resposta do frontend — ajustes aplicados e o que falta decidir

**Data:** 07/09/2026
**Repositório:** SciTech-frontend, branch `main`
**Responde a:** "Ajustes pedidos ao app", backend `main` `10092e6`

Os quatro bloqueadores estão resolvidos. As correções de contrato do §2 e as
três melhorias do §3 também, com uma exceção declarada abaixo (§3.2, o
`GET /meetings`, que depende de uma decisão de vocês). `flutter analyze`
limpo; suíte em **26 testes** (eram 16), todos passando.

Nada disto foi exercitado contra o servidor rodando — continua valendo o §7
do relatório anterior. O que mudou é que o roteiro do teste conjunto agora
não morre no passo 3.

---

## 1. Bloqueadores — resolvidos

### 1.1. 403 no cadastro

Tratado como erro **do campo do e-mail**, com o `detail` do servidor exibido
literalmente. Fica ancorado no campo, visível enquanto o usuário corrige, em
vez de um snackbar que some em segundos — a diferença importa porque, como
vocês apontaram, é condição permanente do endereço e não algo que melhora
tentando de novo.

Sem `detail` no corpo, cai numa frase própria que ainda diz do que se trata
("use seu e-mail institucional"), em vez do texto genérico com o código.

Aproveitamos e movemos o **409** para o mesmo lugar: também é um problema do
endereço digitado, e ficava estranho um aparecer no campo e o outro não. O
401 continua em snackbar — pode ser o e-mail ou a senha, não dá para ancorar.

Coberto por quatro testes em `test/auth_errors_test.dart`.

### 1.2. Contas do teste

Anotado. Vamos usar dois `@ifg.edu.br`. O aviso sobre o `adb reverse`
colapsar tudo em `127.0.0.1` foi para o README — era exatamente o tipo de
coisa que ia nos custar uma hora de teste sem ninguém entender por quê.

### 1.3. O cliente WS já lê em laço

Conferimos: `status_service.dart` usa `stream.listen(...)`, que consome todas
as mensagens até o servidor fechar. Não havia "lê uma e encerra" para
corrigir — o push real está sendo aproveitado.

O que estava errado era a **documentação**: o arquivo dizia, em letras
garrafais, que o `/ws` era um stub de Fase 7 e mandava não confiar nele. Isso
foi reescrito, no código e no README, com o comportamento de hoje (push a
cada segundo, teto de 1h) e com o motivo de o polling continuar.

O polling fica. Concordamos que a remoção é decisão combinada; do nosso lado
ele ainda cobre o teto de 1h, queda de rede e 4401/4404.

---

## 2. Correções de contrato — aplicadas

**2.1. `progress`.** Nunca foi consumido. A tela de processamento sempre
funcionou por estágio, com uma lista de etapas — não há barra nem percentual
para desmontar. Registramos no README que o campo é sempre `null`, para
ninguém tentar de novo daqui a três meses.

**2.2. Estágios curtos.** Também já estava certo, por acaso mais do que por
projeto: a lista de etapas marca como concluída toda etapa anterior ao estado
atual, então um salto de `diarizing` para `extracting` é renderizado
corretamente. Nenhuma tela exige a sequência completa. Escrevemos isso como
comentário na lista de estágios para não se perder numa refatoração futura.

**2.3. 413.** Tratado nas duas rotas, com mensagem específica.

No upload há uma sutileza que vale contar: como o teto é aplicado *durante* a
escrita em disco, o dio pode classificar a resposta como erro de envio em vez
de `badResponse`, dependendo de como o socket é encerrado. Por isso o app
checa `statusCode == 413` **antes** de olhar o tipo do erro — senão o caso
mais provável (a resposta chegando com o corpo ainda subindo) viraria "falha
de rede", que manda o usuário tentar de novo para falhar igual.

Na amostra de voz, os 25 MB são inalcançáveis pelo caminho normal — a folha
de gravação limita a 20 segundos, ~640 KB. O tratamento existe assim mesmo,
marcado como falha permanente, para o caso não ser confundido com rede.

**2.4. `Retry-After`.** A mensagem virou **"aguarde até X minutos"**. Como
vocês descreveram, o número é a janela inteira, então "em ~60 minutos" seria
mentira para mais em quase todo caso; "até" é o que o valor de fato garante.
Não precisa trocar por tempo restante do lado de vocês — a mensagem está
honesta com o que o header significa.

**2.5. Limites.** Anotados no README, com a regra de que só falhas contam e
de que uma tentativa já bloqueada não estende a janela. Os dois riscos de
teste (5 senhas erradas travam a conta A; 10 domínios errados travam o IP)
estão no checklist do §5.

**2.6. `error.code`.** Implementado. Os sete códigos têm tradução em
português em `lib/services/job_errors.dart`, e o `error.message` **não é mais
exibido** — nem como fallback. Código desconhecido cai numa mensagem
genérica; o `str(exc)` não chega à tela em nenhum caminho, o que também
resolve o vazamento de caminho de arquivo do servidor.

O `code` cru aparece em fonte pequena embaixo da mensagem, para o usuário
conseguir repassar a quem for olhar o log — não para interpretar.

Um teste percorre os sete códigos e falha se algum ficar sem tradução; outro
verifica que um `message` com `Traceback`/caminho de arquivo não escapa.

---

## 3. Melhorias

### 3.1. `GET /participants/{id}/voice-profile` — passamos a usar

A tela de participantes abre com o estado local (instantâneo) e, logo depois,
reconcilia com o servidor: para cada participante com amostra, consulta o
`exists` e corrige o selo de sincronizado quando os dois discordam.

Detalhe deliberado: falha de rede devolve "não sei", nunca "não existe".
Tratar o servidor fora do ar como ausência faria a biometria parecer ter
sumido toda vez que a rede caísse.

### 3.2. `GET /meetings` — concordamos com a direção, e a lista de campos não é a parte difícil

Concordamos em migrar. Histórico consistente entre aparelhos é o objetivo
certo, e é para onde o escopo por `user_id` já estava apontando.

**Campos que faltam no `MeetingSummary`:**

1. **Nomes dos participantes** (`participant_names: [str]`, ou
   `participants: [{id, name}]` se for barato). É o que está na segunda linha
   de cada cartão do histórico hoje: `"07/09/2026 · Ana, Bruno, Carla"`.
   **Contagem não substitui** — a tela mostra os nomes, não o número.
2. **`error.code`**, quando `status == "error"`. O `status` sozinho deixa a
   lista mostrar que a reunião falhou, mas não o quê; com o código, o
   histórico usa a mesma tradução do §2.6 e o usuário sabe se vale reenviar.

**Duração: não acrescentem por nossa causa.** Não é exibida em lugar nenhum
hoje. Se for barato, é bem-vinda para uma versão futura do cartão; se custar
alguma coisa, não vale.

**O que de fato bloqueia a migração não são campos, são duas operações.** O
histórico local não é só leitura:

- **Renomear** (`_renameMeeting`). O usuário renomeia reuniões, e é usado —
  o título que vai no upload costuma ser genérico. Sem um
  `PATCH /meetings/{job_id}` com `title`, ou nós perdemos a funcionalidade,
  ou mantemos um mapa local de títulos sobrepostos — que é exatamente a
  divergência entre aparelho e servidor que a migração existe para acabar.
- **Remover** (`_removeMeeting`). Hoje some da lista do aparelho. Vindo do
  servidor, sem `DELETE /meetings/{job_id}` (ou um "ocultar"), a reunião
  reaparece no próximo carregamento — ou precisamos de uma lista local de
  lápides, com o mesmo problema.

Então o pedido é: **os dois campos acima, mais uma decisão sobre renomear e
remover.** Se vocês preferirem que essas duas continuem locais, dá para
migrar assim mesmo, mas aí a migração entrega menos do que promete e é
melhor sabermos disso antes. Não é urgente de nenhum lado; seguimos com o
histórico local até vocês responderem.

Uma coisa que a migração **não** dispensa: o cache local de resultados. Ele
existe para reabrir reunião sem rede e continua, independente de onde a lista
venha.

### 3.3. `isAdmin` — removido

Campo e selo da tela inicial, os dois. Combinado que, se um dia houver
papéis, vocês avisam antes de mexer no schema.

---

## 4. Confirmações — obrigado, e o que fizemos com elas

As três premissas do §3 do relatório anterior estão confirmadas; nada mudou
no código por causa disso, que era o resultado esperado. Duas anotações:

- **Rotação de refresh sem detecção de reuso em cascata.** Isso é um alívio
  real e está registrado no README: hoje, um refresh que escape da
  serialização custa uma chamada com 401, não a conta. **Se vocês
  adicionarem reuse-detection, isso muda de categoria** — a serialização
  passa a ser a diferença entre "uma chamada falhou" e "o usuário foi
  deslogado por usar o app em duas telas". Contamos com o aviso prévio.
- **`user_id` imutável e sem endpoint de exclusão de conta.** É o que
  sustenta o escopo local. Anotado que o cenário de mudança é apagar o
  `jobs.db` na mão — se acontecer, o combinado é vocês avisarem, porque do
  nosso lado o sintoma seria o usuário perder de vista os dados locais dele
  sem nenhum erro aparecer.

O refresh token não aparecer em nenhum campo da resposta: não precisamos
dele, o app já o guarda do próprio `TokenPair`. Sem pedido aqui.

---

## 5. Checklist do teste conjunto

Do lado do app, atualizado com o que vocês mandaram:

1. Dois e-mails **`@ifg.edu.br`** separados antes de começar.
2. Não errar o domínio no cadastro — 10 erros travam o **IP** por 1h, e com
   `adb reverse` isso é o aparelho inteiro, não uma conta.
3. Não errar senha 5 vezes na mesma conta — trava aquele **e-mail** por
   15 min.
4. Subir API **e** worker (`python -m app.worker`).
5. `adb reverse tcp:8000 tcp:8000`, app em `127.0.0.1:8000`.

Os passos 3–7 do roteiro anterior seguem valendo sem mudança.

Sobre o log de 401 e o motivo do fechamento do WS: os `detail` distintos já
resolvem a maior parte do que precisávamos — dá para distinguir token ausente
de inválido pela resposta. O log do lado de vocês continua útil para o caso
em que o app não chega a ver resposta nenhuma, mas não é bloqueante para o
teste.

---

## 6. Resumo

| Item | Situação |
|---|---|
| 1.1 — 403 no cadastro | ✅ tratado, erro no campo do e-mail, com teste |
| 1.2 — contas institucionais | ✅ anotado no README e no checklist |
| 1.3 — WS lido em laço | ✅ já estava; documentação corrigida |
| 2.1 — `progress` sempre `null` | ✅ nunca foi consumido; registrado |
| 2.2 — estágios pulados | ✅ já tolerado; comentado no código |
| 2.3 — 413 nas duas rotas | ✅ tratado, com o cuidado do 413 em pleno envio |
| 2.4 — `Retry-After` | ✅ "aguarde até X minutos" |
| 2.5 — limites de rate limit | ✅ documentados |
| 2.6 — `error.code` | ✅ sete traduções; `message` cru nunca exibido |
| 3.1 — `voice-profile` | ✅ consumido, com reconciliação na abertura da tela |
| 3.2 — `GET /meetings` | ⏳ **aguardando vocês**: 2 campos + decisão sobre renomear/remover |
| 3.3 — `isAdmin` | ✅ removido |
